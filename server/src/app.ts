import Fastify, { type FastifyInstance, type FastifyRequest } from "fastify";
import { ZodError } from "zod";

import { quotaFor } from "./config.js";
import { ActivityBatchSchema, ActivityService } from "./habit/activity.js";
import { dateKey, localDateKey, weekKey } from "./habit/engine.js";
import { LeagueService } from "./habit/leagues.js";
import { SegmentRequestSchema } from "./segmentation/schema.js";
import { QuotaExceeded, SegmentService, TierNotEligible, type Caller } from "./segmentation/service.js";
import type { QuotaStore } from "./stores/memory.js";

export interface AppDeps {
  segments: SegmentService;
  quota: QuotaStore;
  activity?: ActivityService;
  leagues?: LeagueService;
  /** Phase 7 replaces this with Firebase ID-token verification. */
  resolveCaller?: (req: FastifyRequest) => Caller | undefined;
}

class Unauthorized extends Error {}

const DEVICE_ID = /^[a-f0-9]{16,64}$/;

export function deviceCaller(req: FastifyRequest): Caller | undefined {
  const id = req.headers["x-device-id"];
  if (typeof id !== "string" || !DEVICE_ID.test(id)) return undefined;
  const region = req.headers["x-region"];
  return { userId: `device:${id}`, region: typeof region === "string" ? region : undefined };
}

export function buildApp(deps: AppDeps): FastifyInstance {
  const app = Fastify({ logger: process.env.NODE_ENV !== "test", bodyLimit: 8 * 1024 * 1024 });
  const activity = deps.activity ?? new ActivityService();
  const leagues = deps.leagues ?? new LeagueService(activity);
  const resolve = deps.resolveCaller ?? deviceCaller;

  const caller = (req: FastifyRequest): Caller => {
    const c = resolve(req);
    if (!c) throw new Unauthorized("missing or invalid credentials");
    return c;
  };
  const tzOffset = (req: FastifyRequest): number => {
    const v = Number(req.headers["x-tz-offset"] ?? 0);
    return Number.isFinite(v) ? Math.max(-840, Math.min(840, Math.trunc(v))) : 0;
  };
  const today = (req: FastifyRequest) => localDateKey(new Date(), tzOffset(req));

  app.setErrorHandler((err, _req, reply) => {
    if (err instanceof ZodError) return reply.code(400).send({ error: "invalid_request", issues: err.issues.slice(0, 10) });
    if (err instanceof Unauthorized) return reply.code(401).send({ error: "unauthorized" });
    if (err instanceof QuotaExceeded) return reply.code(402).send({ error: "quota_exceeded", limit: err.limit });
    if (err instanceof TierNotEligible) return reply.code(403).send({ error: "tier_not_eligible", message: err.message });
    const status = (err as { statusCode?: number }).statusCode;
    if (status && status < 500) return reply.code(status).send({ error: (err as Error).message });
    app.log.error(err);
    return reply.code(500).send({ error: "internal" });
  });

  app.get("/healthz", async () => ({ ok: true }));

  // ------------------------------------------------------------ segmentation
  app.post("/v1/segment", async (req, reply) => {
    const c = caller(req);
    const body = SegmentRequestSchema.parse(req.body);
    if (body.priority === "background") {
      const res = await deps.segments.submitBackground(body, c);
      if ("jobId" in res) return reply.code(202).send({ job_id: res.jobId });
      return res;
    }
    return deps.segments.segment(body, c);
  });

  app.get<{ Params: { id: string } }>("/v1/segment/jobs/:id", async (req, reply) => {
    const job = await deps.segments.pollJob(req.params.id, caller(req));
    if (!job) return reply.code(404).send({ error: "not_found" });
    return { status: job.status, ...(job.result ?? {}) };
  });

  app.get<{ Querystring: { tier?: string } }>("/v1/me/ai-usage", async (req) => {
    const c = caller(req);
    const tier = (req.query.tier ?? "plus") as "plus" | "pro" | "scholar";
    const period = new Date().toISOString().slice(0, 7);
    const used = await deps.quota.booksUsed(c.userId, period);
    return { period, books_used: used.size, books_limit: quotaFor(tier, c.region) };
  });

  // ------------------------------------------------------------ habit & social
  app.post("/v1/activity/batch", async (req) => {
    const c = caller(req);
    const body = ActivityBatchSchema.parse(req.body);
    const result = activity.ingest(c.userId, body);
    leagues.join(c.userId, weekKey(today(req)));
    return result;
  });

  app.post<{ Body: { title?: string } }>("/v1/activity/book-finished", async (req) => {
    activity.bookFinished(caller(req).userId, String(req.body?.title ?? "a book"));
    return { ok: true };
  });

  app.put<{ Body: { display_name?: string; daily_goal_cards?: number; freezes_per_week?: number } }>(
    "/v1/me/profile",
    async (req) => {
      const u = activity.setProfile(caller(req).userId, {
        displayName: req.body?.display_name,
        dailyGoalCards: req.body?.daily_goal_cards,
        freezesPerWeek: req.body?.freezes_per_week,
      });
      return { display_name: u.displayName, daily_goal_cards: u.dailyGoalCards, freezes_per_week: u.freezesPerWeek };
    },
  );

  app.get("/v1/me/streak", async (req) => activity.streakOf(caller(req).userId, today(req)));

  app.get("/v1/leagues/current", async (req, reply) => {
    const s = leagues.standings(caller(req).userId, weekKey(today(req)));
    if (!s) return reply.code(404).send({ error: "not_in_league" });
    return s;
  });

  app.get("/v1/leaderboards/friends", async (req) => ({
    week: weekKey(today(req)),
    rows: activity.friendsLeaderboard(caller(req).userId, weekKey(today(req))),
  }));

  app.post<{ Params: { userId: string } }>("/v1/social/follow/:userId", async (req) => {
    activity.follow(caller(req).userId, req.params.userId);
    return { ok: true };
  });

  app.delete<{ Params: { userId: string } }>("/v1/social/follow/:userId", async (req) => {
    activity.unfollow(caller(req).userId, req.params.userId);
    return { ok: true };
  });

  app.get("/v1/feed", async (req) => ({ items: activity.feedFor(caller(req).userId) }));

  app.post<{ Params: { id: string } }>("/v1/activities/:id/kudos", async (req, reply) => {
    if (!activity.kudos(caller(req).userId, req.params.id)) return reply.code(404).send({ error: "not_found" });
    return { ok: true };
  });

  app.get("/v1/time", async () => ({ today_utc: dateKey(new Date()) }));

  return app;
}
