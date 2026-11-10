import Fastify, { type FastifyInstance, type FastifyRequest } from "fastify";
import { ZodError } from "zod";

import { AuthError, Authenticator } from "./auth.js";
import { quotaFor } from "./config.js";
import type { Db } from "./db/db.js";
import { ActivityBatchSchema, ActivityService } from "./habit/activity.js";
import { localDateKey, weekKey } from "./habit/engine.js";
import { LeagueService } from "./habit/leagues.js";
import { SegmentRequestSchema } from "./segmentation/schema.js";
import { QuotaExceeded, SegmentService, TierNotEligible, type Caller } from "./segmentation/service.js";
import type { Track } from "./music/catalog.js";
import { MusicPicker, MusicPlanRequestSchema, type TrackChooser } from "./music/picker.js";
import { landingPage, ShareSchema, ShareService } from "./social/shares.js";
import { SyncPushSchema, SyncService } from "./social/sync.js";
import type { QuotaStore } from "./stores/memory.js";

export interface AppDeps {
  db: Db;
  segments: SegmentService;
  quota: QuotaStore;
  auth?: Authenticator;
  /** Public base URL for share and invite links, e.g. https://bookreel.app */
  publicBaseUrl?: string;
  /** SHA-256 signing-certificate fingerprints for Android App Links. */
  androidCertFingerprints?: string[];
  /** Licensed soundtrack catalog (paid tiers). */
  music?: Track[];
  /** AI music supervisor (picks tracks for the chapter's music cues). */
  musicChooser?: TrackChooser;
  logger?: boolean;
}

const ANDROID_PACKAGE = "app.bookreel.book_reel";

export function buildApp(deps: AppDeps): FastifyInstance {
  const app = Fastify({ logger: deps.logger ?? false, bodyLimit: 8 * 1024 * 1024 });
  const baseUrl = (deps.publicBaseUrl ?? "http://localhost:8787").replace(/\/$/, "");
  const activity = new ActivityService(deps.db);
  const leagues = new LeagueService(deps.db, activity);
  const sync = new SyncService(deps.db);
  const shares = new ShareService(deps.db, baseUrl);
  const auth = deps.auth ?? new Authenticator(deps.db);
  const picker = new MusicPicker(deps.music ?? [], deps.musicChooser);
  const paid = (tier: string) => ["plus", "pro", "scholar"].includes(tier);

  const caller = async (req: FastifyRequest): Promise<Caller> => {
    const c = await auth.resolve(req);
    await activity.user(c.userId);
    return c;
  };
  const tzOffset = (req: FastifyRequest): number => {
    const v = Number(req.headers["x-tz-offset"] ?? 0);
    return Number.isFinite(v) ? Math.max(-840, Math.min(840, Math.trunc(v))) : 0;
  };
  const week = (req: FastifyRequest) => weekKey(localDateKey(new Date(), tzOffset(req)));

  app.setErrorHandler((err, _req, reply) => {
    if (err instanceof ZodError) return reply.code(400).send({ error: "invalid_request", issues: err.issues.slice(0, 10) });
    if (err instanceof AuthError) return reply.code(401).send({ error: "unauthorized", message: err.message });
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
    const c = await caller(req);
    const body = SegmentRequestSchema.parse(req.body);
    if (body.priority === "background") {
      const res = await deps.segments.submitBackground(body, c);
      if ("jobId" in res) return reply.code(202).send({ job_id: res.jobId });
      return res;
    }
    return deps.segments.segment(body, c);
  });

  app.get<{ Params: { id: string } }>("/v1/segment/jobs/:id", async (req, reply) => {
    const job = await deps.segments.pollJob(req.params.id, await caller(req));
    if (!job) return reply.code(404).send({ error: "not_found" });
    return { status: job.status, ...(job.result ?? {}) };
  });

  app.get<{ Querystring: { tier?: string } }>("/v1/me/ai-usage", async (req) => {
    const c = await caller(req);
    const tier = (req.query.tier ?? "plus") as "plus" | "pro" | "scholar";
    const period = new Date().toISOString().slice(0, 7);
    const used = await deps.quota.booksUsed(c.userId, period);
    return { period, books_used: used.size, books_limit: quotaFor(tier, c.region) };
  });

  // ------------------------------------------------------------ profile & habit
  app.get("/v1/me", async (req) => {
    const c = await caller(req);
    const u = await activity.user(c.userId);
    return {
      user_id: u.id,
      display_name: u.display_name,
      invite_code: u.invite_code,
      invite_url: `${baseUrl}/i/${u.invite_code}`,
      daily_goal_cards: u.daily_goal_cards,
      signed_in: !u.id.startsWith("device:"),
    };
  });

  app.put<{ Body: { display_name?: string; daily_goal_cards?: number; freezes_per_week?: number } }>("/v1/me/profile", async (req) => {
    const u = await activity.setProfile((await caller(req)).userId, {
      displayName: req.body?.display_name,
      dailyGoalCards: req.body?.daily_goal_cards,
      freezesPerWeek: req.body?.freezes_per_week,
    });
    return { display_name: u.display_name, daily_goal_cards: u.daily_goal_cards, freezes_per_week: u.freezes_per_week };
  });

  app.post("/v1/activity/batch", async (req) => {
    const c = await caller(req);
    const body = ActivityBatchSchema.parse(req.body);
    const result = await activity.ingest(c.userId, body);
    await leagues.join(c.userId, week(req));
    return result;
  });

  app.post<{ Body: { title?: string } }>("/v1/activity/book-finished", async (req) => {
    await activity.bookFinished((await caller(req)).userId, String(req.body?.title ?? "a book"));
    return { ok: true };
  });

  app.get("/v1/me/streak", async (req) => activity.streakOf((await caller(req)).userId, localDateKey(new Date(), tzOffset(req))));

  // ------------------------------------------------------------ social
  app.get("/v1/leagues/current", async (req, reply) => {
    const s = await leagues.standings((await caller(req)).userId, week(req));
    if (!s) return reply.code(404).send({ error: "not_in_league" });
    return s;
  });

  app.get("/v1/leaderboards/friends", async (req) => ({
    week: week(req),
    rows: await activity.friendsLeaderboard((await caller(req)).userId, week(req)),
  }));

  app.post<{ Body: { code?: string } }>("/v1/social/follow-code", async (req, reply) => {
    const friend = await activity.followByCode((await caller(req)).userId, String(req.body?.code ?? ""));
    if (!friend) return reply.code(404).send({ error: "unknown_code" });
    return { friend };
  });

  app.delete<{ Params: { userId: string } }>("/v1/social/follow/:userId", async (req) => {
    await activity.unfollow((await caller(req)).userId, req.params.userId);
    return { ok: true };
  });

  app.get("/v1/feed", async (req) => ({ items: await activity.feedFor((await caller(req)).userId) }));

  app.post<{ Params: { id: string } }>("/v1/activities/:id/kudos", async (req, reply) => {
    if (!(await activity.kudos((await caller(req)).userId, req.params.id))) return reply.code(404).send({ error: "not_found" });
    return { ok: true };
  });

  // ------------------------------------------------------------ sync
  app.put("/v1/sync", async (req) => sync.push((await caller(req)).userId, SyncPushSchema.parse(req.body)));

  app.get<{ Querystring: { since?: string } }>("/v1/sync", async (req) =>
    sync.pull((await caller(req)).userId, Math.max(0, Number(req.query.since ?? 0) || 0)),
  );

  // ------------------------------------------------------------ soundtrack (paid)
  app.get<{ Querystring: { tier?: string } }>("/v1/music/tracks", async (req, reply) => {
    await caller(req);
    // Entitlements arrive with Play Billing (Phase 8); until then the tier is the client's claim, as for /v1/segment.
    const tier = req.query.tier ?? "free";
    if (!paid(tier)) {
      return reply.code(403).send({ error: "tier_not_eligible", message: "The soundtrack is available on Plus, Pro and Scholar." });
    }
    return { tracks: deps.music ?? [] };
  });

  // The AI picks the best catalog track for each of a chapter's music cues.
  app.post("/v1/music/plan", async (req, reply) => {
    await caller(req);
    const body = MusicPlanRequestSchema.parse(req.body);
    if (!paid(body.tier)) {
      return reply.code(403).send({ error: "tier_not_eligible", message: "The soundtrack is available on Plus, Pro and Scholar." });
    }
    return picker.plan(body);
  });

  // ------------------------------------------------------------ share links & web pages
  app.post("/v1/share", async (req) => shares.create((await caller(req)).userId, ShareSchema.parse(req.body)));

  app.get<{ Params: { id: string } }>("/c/:id", async (req, reply) => {
    const html = await shares.page(req.params.id);
    if (!html) return reply.code(404).type("text/html").send(landingPage({ title: "Not found", description: "", url: baseUrl, body: "<h1>This link has expired.</h1>" }));
    return reply.type("text/html; charset=utf-8").send(html);
  });

  app.get<{ Params: { code: string } }>("/i/:code", async (req, reply) => {
    const code = req.params.code.replace(/[^A-Za-z0-9]/g, "").slice(0, 12).toUpperCase();
    return reply.type("text/html; charset=utf-8").send(
      landingPage({
        title: "Read with me on BookReel",
        description: "Books as bite-sized cards. Let's keep each other going.",
        url: `${baseUrl}/i/${code}`,
        body: `<h1>Read with me on BookReel</h1><p>Install the app, open <strong>Friends → Add a friend</strong> and enter this code:</p><p style="font-size:2rem;letter-spacing:.2em;color:inherit"><strong>${code}</strong></p>`,
      }),
    );
  });

  app.get("/.well-known/assetlinks.json", async () =>
    (deps.androidCertFingerprints ?? []).length === 0
      ? []
      : [
          {
            relation: ["delegate_permission/common.handle_all_urls"],
            target: { namespace: "android_app", package_name: ANDROID_PACKAGE, sha256_cert_fingerprints: deps.androidCertFingerprints },
          },
        ],
  );

  return app;
}
