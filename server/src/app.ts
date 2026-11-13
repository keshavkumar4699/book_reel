import Fastify, { type FastifyInstance, type FastifyRequest } from "fastify";
import { z, ZodError } from "zod";

import { AccountService } from "./account.js";
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
import { ActivityBatchSchema, ActivityService, CannotFollowSelf, HandleTaken, InvalidHandle, NotFollowable } from "./habit/activity.js";
import { localDateKey, weekKey } from "./habit/engine.js";
import { CommentSchema, FeedService, NotVisible, SessionSchema } from "./habit/feed.js";
import { LeagueService } from "./habit/leagues.js";
import { MoodInvalid, MoodQuotaExceeded, MoodSuggestSchema, MoodUnavailable, type MoodService } from "./mood/suggest.js";
import { SegmentRequestSchema } from "./segmentation/schema.js";
import { QuotaExceeded, SegmentService, TierNotEligible, type Caller } from "./segmentation/service.js";
import { escapeHtml, landingPage, ShareSchema, ShareService } from "./social/shares.js";
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
  genres: z.array(z.string().max(60)).max(12).optional(),
  reading: z.string().max(300).optional(),
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
  /** Gemma mood suggestions; without it the app predicts the mood on its own. */
  mood?: MoodService;
  /** Play Billing; without it plans are not verified (development). */
  billing?: BillingService;
  /** Shared secret in the Pub/Sub push URL for Play notifications (?secret=…). */
  rtdnSecret?: string;
  /** Where readers without the app can ask for their account to be deleted. */
  supportEmail?: string;
  logger?: boolean;
}

const ANDROID_PACKAGE = "app.sweatik2.cloro";

export function buildApp(deps: AppDeps): FastifyInstance {
  const app = Fastify({ logger: deps.logger ?? false, bodyLimit: 8 * 1024 * 1024 });
  const baseUrl = (deps.publicBaseUrl ?? "http://localhost:8787").replace(/\/$/, "");
  const activity = new ActivityService(deps.db);
  const feeds = new FeedService(deps.db);
  const accounts = new AccountService(deps.db);
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
    if (err instanceof NotVisible) return reply.code(404).send({ error: "not_found" });
    if (err instanceof NotFollowable) return reply.code(404).send({ error: "not_found", message: err.message });
    if (err instanceof CannotFollowSelf) return reply.code(400).send({ error: "follow_self", message: err.message });
    if (err instanceof MoodQuotaExceeded) return reply.code(429).send({ error: "mood_quota", limit: err.limit });
    if (err instanceof MoodUnavailable) return reply.code(503).send({ error: "mood_unavailable", message: err.message });
    if (err instanceof MoodInvalid) return reply.code(502).send({ error: "mood_invalid", message: err.message });
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
      genres: u.genres ? u.genres.split(",").filter(Boolean) : [],
      reading: u.reading,
      ...(await activity.counts(u.id)),
      invite_code: u.invite_code,
      invite_url: `${baseUrl}/i/${u.invite_code}`,
      daily_goal_cards: u.daily_goal_cards,
      signed_in: !u.id.startsWith("device:"),
    };
  });

  // Your data (Production plan A3): download all of it, or delete the account.
  app.get("/v1/me/export", async (req, reply) => {
    const data = await accounts.export((await caller(req)).userId);
    return reply.header("content-disposition", 'attachment; filename="cloro-export.json"').send(data);
  });

  app.delete("/v1/me", async (req, reply) => {
    // Resolve without creating: deleting an account that doesn't exist is a no-op.
    const c = await auth.resolve(req);
    await accounts.delete(c.userId);
    return reply.code(204).send();
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
      genres: b.genres,
      reading: b.reading,
    });
    return {
      display_name: u.display_name,
      handle: u.handle,
      pronouns: u.pronouns,
      bio: u.bio,
      avatar: u.avatar,
      genres: u.genres ? u.genres.split(",").filter(Boolean) : [],
      reading: u.reading,
      daily_goal_cards: u.daily_goal_cards,
      freezes_per_week: u.freezes_per_week,
    };
  });

  app.post("/v1/activity/batch", async (req) => {
    const c = await caller(req);
    const body = ActivityBatchSchema.parse(req.body);
    const result = await activity.ingest(c.userId, body);
    await leagues.join(c.userId, week(req));
    const u = await activity.user(c.userId);
    await feeds.checkBestWeek(c.userId, u.display_name, localDateKey(new Date(), tzOffset(req)));
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

  // Strava-style follows: one way, with public counts and lists.
  app.post<{ Params: { userId: string } }>("/v1/social/follow/:userId", async (req) => {
    await activity.follow((await caller(req)).userId, req.params.userId);
    return { ok: true };
  });

  app.post<{ Body: { handle?: string } }>("/v1/social/follow-handle", async (req) => ({
    user: await activity.followByHandle((await caller(req)).userId, String(req.body?.handle ?? "")),
  }));

  /** "me", a user id, or "@handle". */
  const reader = async (req: FastifyRequest<{ Params: { id: string } }>) => {
    const c = await caller(req);
    const u = await activity.visible(req.params.id === "me" ? c.userId : req.params.id, c.userId);
    if (!u) throw new NotFollowable("No reader found.");
    return { viewer: c.userId, u };
  };

  app.get<{ Params: { id: string } }>("/v1/users/:id", async (req) => {
    const { viewer, u } = await reader(req);
    return activity.publicProfile(u.id, viewer, localDateKey(new Date(), tzOffset(req)));
  });

  app.get<{ Params: { id: string } }>("/v1/users/:id/followers", async (req) => {
    const { viewer, u } = await reader(req);
    return { items: await activity.people(u.id, viewer, "followers") };
  });

  app.get<{ Params: { id: string } }>("/v1/users/:id/following", async (req) => {
    const { viewer, u } = await reader(req);
    return { items: await activity.people(u.id, viewer, "following") };
  });

  // The Today feed: your sessions and milestones and those of readers you follow.
  app.get<{ Querystring: { before?: string; limit?: string } }>("/v1/feed", async (req) => {
    const before = req.query.before && !Number.isNaN(Date.parse(req.query.before)) ? req.query.before : undefined;
    return { items: await feeds.feedFor((await caller(req)).userId, { before, limit: Number(req.query.limit) || 20 }) };
  });

  app.post("/v1/activities/session", async (req) => {
    const posted = await feeds.postSession((await caller(req)).userId, SessionSchema.parse(req.body));
    return { id: posted?.id ?? null };
  });

  app.post<{ Params: { id: string } }>("/v1/activities/:id/kudos", async (req, reply) => {
    if (!(await feeds.kudos((await caller(req)).userId, req.params.id))) return reply.code(404).send({ error: "not_found" });
    return { ok: true };
  });

  app.get<{ Params: { id: string } }>("/v1/activities/:id/comments", async (req) => ({
    items: await feeds.comments((await caller(req)).userId, req.params.id),
  }));

  app.post<{ Params: { id: string } }>("/v1/activities/:id/comments", async (req) => ({
    comment: await feeds.addComment((await caller(req)).userId, req.params.id, CommentSchema.parse(req.body).text),
  }));

  app.delete<{ Params: { id: string } }>("/v1/comments/:id", async (req, reply) => {
    if (!(await feeds.deleteComment((await caller(req)).userId, req.params.id))) return reply.code(404).send({ error: "not_found" });
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

  // ------------------------------------------------------------ mood (Gemma)
  // Only the mood log (weekday, hour, mood, minutes) is accepted: the schema is strict.
  app.post("/v1/mood/suggest", async (req, reply) => {
    const c = await caller(req);
    const body = MoodSuggestSchema.parse(req.body);
    body.tier = await billing.tierFor(c.userId, body.tier);
    if (!deps.mood) return reply.code(503).send({ error: "mood_unavailable", message: "No mood model is configured." });
    return deps.mood.suggest(c.userId, body);
  });

  // ------------------------------------------------------------ share links & web pages
  app.post("/v1/share", async (req) => shares.create((await caller(req)).userId, ShareSchema.parse(req.body)));

  app.get<{ Params: { id: string } }>("/c/:id", async (req, reply) => {
    const html = await shares.page(req.params.id);
    if (!html) return reply.code(404).type("text/html").send(landingPage({ title: "Not found", description: "", url: baseUrl, body: "<h1>This link has expired.</h1>" }));
    return reply.type("text/html; charset=utf-8").send(html);
  });

  // For Google Play's account-deletion form: how to delete an account.
  app.get("/account/delete", async (_req, reply) => {
    const email = deps.supportEmail ? escapeHtml(deps.supportEmail) : null;
    return reply.type("text/html; charset=utf-8").send(
      landingPage({
        title: "Delete your Cloro account",
        description: "How to delete your Cloro account and data.",
        url: `${baseUrl}/account/delete`,
        body:
          `<h1>Delete your Cloro account</h1>` +
          `<p>In the app, open <strong>Profile → ⚙ Settings → You → Delete account</strong>. ` +
          `This erases your profile, followers and following, reading activity, comments and kudos, synced notes and share links ` +
          `from our servers straight away. Books and notes stored only on your phone are removed when you uninstall the app.</p>` +
          `<p>You can download a copy first: <strong>Settings → You → Download my data</strong>.</p>` +
          (email
            ? `<p>No longer have the app? Email <a href="mailto:${email}?subject=Delete%20my%20Cloro%20account">${email}</a> ` +
              `from the address on your account, or with your @username, and we'll delete it within 30 days.</p>`
            : "") +
          `<p>Subscriptions are billed by Google Play: cancel them in the Play Store app under <strong>Payments &amp; subscriptions</strong>.</p>`,
      }),
    );
  });

  app.get<{ Params: { code: string } }>("/i/:code", async (req, reply) => {
    const code = req.params.code.replace(/[^A-Za-z0-9]/g, "").slice(0, 12).toUpperCase();
    return reply.type("text/html; charset=utf-8").send(
      landingPage({
        title: "Read with me on Cloro",
        description: "Books as bite-sized cards. Let's keep each other going.",
        url: `${baseUrl}/i/${code}`,
        body: `<h1>Read with me on Cloro</h1><p>Install the app, open <strong>Profile → Find people</strong> and enter this code:</p><p style="font-size:2rem;letter-spacing:.2em;color:inherit"><strong>${code}</strong></p>`,
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
