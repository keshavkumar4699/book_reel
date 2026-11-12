import Fastify, { type FastifyInstance, type FastifyRequest } from "fastify";
import { z, ZodError } from "zod";

import { AuthError, Authenticator } from "./auth.js";
import {
  BillingService,
  BillingUnavailable,
  InvalidPurchase,
  purchaseTokenFromRtdn,
  VerifyPurchaseSchema,
} from "./billing/play.js";
import { isPaidTier, quotaFor } from "./config.js";
import type { Db } from "./db/db.js";
import { ActivityBatchSchema, ActivityService, HandleTaken, InvalidHandle } from "./habit/activity.js";
import { localDateKey, weekKey } from "./habit/engine.js";
import { LeagueService } from "./habit/leagues.js";
import { SegmentRequestSchema } from "./segmentation/schema.js";
import { QuotaExceeded, SegmentService, TierNotEligible, type Caller } from "./segmentation/service.js";
import { landingPage, ShareSchema, ShareService } from "./social/shares.js";
import { SyncPushSchema, SyncService } from "./social/sync.js";
import type { QuotaStore } from "./stores/memory.js";
import { SpeechQuotaExceeded, SpeechRequestSchema, SpeechUnavailable, type SpeechService } from "./speech/tts.js";
import { BookProfiler, BookProfileRequestSchema, type VoiceChooser } from "./typography/profile.js";

const ProfileBodySchema = z.object({
  display_name: z.string().max(80).optional(),
  daily_goal_cards: z.number().optional(),
  freezes_per_week: z.number().optional(),
  handle: z.string().max(40).optional(),
  pronouns: z.string().max(60).optional(),
  bio: z.string().max(400).optional(),
  avatar: z.string().max(32).optional(),
});

export interface AppDeps {
  db: Db;
  segments: SegmentService;
  quota: QuotaStore;
  auth?: Authenticator;
  /** Public base URL for share and invite links, e.g. https://bookreel.app */
  publicBaseUrl?: string;
  /** SHA-256 signing-certificate fingerprints for Android App Links. */
  androidCertFingerprints?: string[];
  /** AI book designer (picks each book's typographic voice). */
  voiceChooser?: VoiceChooser;
  /** Natural read-aloud voice; without it the app uses the phone's voice. */
  speech?: SpeechService;
  /** Play Billing; without it plans are not verified (development). */
  billing?: BillingService;
  /** Shared secret in the Pub/Sub push URL for Play notifications (?secret=…). */
  rtdnSecret?: string;
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
  const profiler = new BookProfiler(deps.voiceChooser);
  const billing = deps.billing ?? new BillingService(deps.db, undefined);
  const entitlementJson = (e: { tier: string; productId: string | null; expiresAt: Date | null; state: string | null }) => ({
    tier: e.tier,
    product_id: e.productId,
    expires_at: e.expiresAt?.toISOString() ?? null,
    state: e.state,
    enforced: billing.enforced,
  });

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
    if (err instanceof HandleTaken) return reply.code(409).send({ error: "handle_taken", message: err.message });
    if (err instanceof SpeechQuotaExceeded) return reply.code(429).send({ error: "speech_quota", limit: err.limit });
    if (err instanceof InvalidPurchase) return reply.code(400).send({ error: "invalid_purchase", message: err.message });
    if (err instanceof BillingUnavailable) return reply.code(503).send({ error: "billing_unavailable", message: err.message });
    if (err instanceof SpeechUnavailable) return reply.code(503).send({ error: "tts_unavailable", message: err.message });
    if (err instanceof InvalidHandle) return reply.code(400).send({ error: "invalid_handle", message: err.message });
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
    body.tier = await billing.tierFor(c.userId, body.tier);
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
    const asked = await billing.tierFor(c.userId, req.query.tier ?? "");
    const tier = isPaidTier(asked) ? asked : "lite";
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
      handle: u.handle,
      pronouns: u.pronouns,
      bio: u.bio,
      avatar: u.avatar,
      invite_code: u.invite_code,
      invite_url: `${baseUrl}/i/${u.invite_code}`,
      daily_goal_cards: u.daily_goal_cards,
      signed_in: !u.id.startsWith("device:"),
    };
  });

  app.put("/v1/me/profile", async (req) => {
    const b = ProfileBodySchema.parse(req.body ?? {});
    const u = await activity.setProfile((await caller(req)).userId, {
      displayName: b.display_name,
      dailyGoalCards: b.daily_goal_cards,
      freezesPerWeek: b.freezes_per_week,
      handle: b.handle,
      pronouns: b.pronouns,
      bio: b.bio,
      avatar: b.avatar,
    });
    return {
      display_name: u.display_name,
      handle: u.handle,
      pronouns: u.pronouns,
      bio: u.bio,
      avatar: u.avatar,
      daily_goal_cards: u.daily_goal_cards,
      freezes_per_week: u.freezes_per_week,
    };
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

  // ------------------------------------------------------------ book typography
  app.post("/v1/book/profile", async (req, reply) => {
    await caller(req);
    const body = BookProfileRequestSchema.parse(req.body);
    body.tier = await billing.tierFor((await caller(req)).userId, body.tier);
    if (!isPaidTier(body.tier)) {
      return reply.code(403).send({ error: "tier_not_eligible", message: "AI book design is available on Lite, Plus, Pro and Scholar." });
    }
    return profiler.profile(body);
  });

  // ------------------------------------------------------------ billing
  app.post("/v1/billing/verify", async (req) => {
    const c = await caller(req);
    const body = VerifyPurchaseSchema.parse(req.body);
    return entitlementJson(await billing.verify(c.userId, body.product_id, body.purchase_token));
  });

  app.get("/v1/billing/entitlement", async (req) => entitlementJson(await billing.current((await caller(req)).userId)));

  // Play real-time developer notifications, pushed by Pub/Sub.
  app.post<{ Querystring: { secret?: string } }>("/v1/billing/rtdn", async (req, reply) => {
    if (!deps.rtdnSecret || req.query.secret !== deps.rtdnSecret) return reply.code(403).send({ error: "forbidden" });
    const token = purchaseTokenFromRtdn(req.body);
    if (token) await billing.refresh(token);
    return reply.code(204).send();
  });

  // ------------------------------------------------------------ read aloud
  app.post("/v1/tts", async (req, reply) => {
    const c = await caller(req);
    const body = SpeechRequestSchema.parse(req.body);
    body.tier = await billing.tierFor(c.userId, body.tier);
    if (!deps.speech) return reply.code(503).send({ error: "tts_unavailable", message: "No speech provider is configured." });
    const out = await deps.speech.speak(c.userId, body);
    return reply
      .header("content-type", out.contentType)
      .header("cache-control", "private, max-age=31536000, immutable")
      .header("x-cache", out.cached ? "hit" : "miss")
      .send(out.audio);
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
