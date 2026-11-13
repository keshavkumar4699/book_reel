import Anthropic from "@anthropic-ai/sdk";

import { buildApp } from "./app.js";
import { Authenticator, FirebaseVerifier } from "./auth.js";
import { openDb } from "./db/db.js";
import { ClaudeVoiceChooser } from "./typography/profile.js";
import { AnthropicBatchClient } from "./segmentation/batch.js";
import { ClaudeSegmenter } from "./segmentation/claudeSegmenter.js";
import { SegmentService } from "./segmentation/service.js";
import { BillingService, verifierFromEnv } from "./billing/play.js";
import { cloudLoggerOptions } from "./logging.js";
import { MoodService, moodModelFromEnv } from "./mood/suggest.js";
import { SpeechService, speechProviderFromEnv } from "./speech/tts.js";
import { SqlJobStore, SqlQuotaStore, SqlSegmentCache, SqlUsageLog } from "./stores/sql.js";

/**
 * Configuration (all optional for local development):
 * - DATABASE_URL         postgres://… for Postgres; otherwise a PGlite data dir (default ./data/pglite)
 * - ANTHROPIC_API_KEY    Claude credentials (or an `ant auth login` profile)
 * - FIREBASE_PROJECT_ID  enables Google sign-in (Firebase ID tokens)
 * - PUBLIC_BASE_URL      base for share/invite links (default http://localhost:PORT)
 * - ANDROID_CERT_SHA256  comma-separated signing-cert fingerprints for App Links
 * - TTS_API_KEY          enables the natural read-aloud voice (secret: set it in the host's secret store)
 * - TTS_BASE_URL         OpenAI-compatible speech API (default https://api.deepinfra.com/v1/openai)
 * - TTS_MODEL            speech model (default hexgrad/Kokoro-82M)
 * - MOOD_API_KEY         enables Gemma mood suggestions (secret; falls back to TTS_API_KEY, the same provider)
 * - MOOD_BASE_URL        OpenAI-compatible chat API (default https://api.deepinfra.com/v1/openai)
 * - MOOD_MODEL           mood model (default google/gemma-3-12b-it)
 * - PLAY_PACKAGE_NAME    Android package name, for Play Billing
 * - PLAY_SERVICE_ACCOUNT_JSON  service-account key with Play Console access (secret)
 * - PLAY_RTDN_SECRET     secret in the Pub/Sub push URL for Play notifications (secret)
 * - BILLING_ENFORCED=1   serve the verified plan instead of the one the app asks for
 * - SUPPORT_EMAIL        shown on /account/delete for readers who no longer have the app
 * - MODERATION_WORDS_FILE  words and phrases (one per line) kept out of names, bios and comments
 * - ADMIN_TOKEN          enables report review at /v1/admin/reports (secret; sent as x-admin-token)
 * - TRUST_PROXY=1        behind a load balancer (Cloud Run): rate limits use the client's address
 */
const port = Number(process.env.PORT ?? 8787);
// In production the database must be Postgres: a container's disk is wiped on
// every restart, so the embedded fallback would silently lose everyone's data.
if (process.env.NODE_ENV === "production" && !/^postgres(ql)?:\/\//.test(process.env.DATABASE_URL ?? "")) {
  console.error("DATABASE_URL must be a postgres:// URL in production (see docs/DEPLOY.md).");
  process.exit(1);
}
const db = await openDb(process.env.DATABASE_URL ?? "./data/pglite");
const client = new Anthropic();
const quota = new SqlQuotaStore(db);
const segments = new SegmentService({
  cache: new SqlSegmentCache(db),
  quota,
  usage: new SqlUsageLog(db),
  jobs: new SqlJobStore(db),
  model: new ClaudeSegmenter(client),
  batch: new AnthropicBatchClient(client),
});
const projectId = process.env.FIREBASE_PROJECT_ID;
const speechProvider = speechProviderFromEnv();
const moodModel = moodModelFromEnv();
const app = buildApp({
  db,
  segments,
  quota,
  auth: new Authenticator(db, projectId ? new FirebaseVerifier(projectId) : undefined),
  publicBaseUrl: process.env.PUBLIC_BASE_URL ?? `http://localhost:${port}`,
  androidCertFingerprints: process.env.ANDROID_CERT_SHA256?.split(",").map((s) => s.trim()).filter(Boolean),
  voiceChooser: new ClaudeVoiceChooser(client),
  speech: speechProvider ? new SpeechService(db, speechProvider) : undefined,
  mood: moodModel ? new MoodService(db, moodModel) : undefined,
  billing: new BillingService(db, verifierFromEnv(), { enforced: process.env.BILLING_ENFORCED === "1" }),
  rtdnSecret: process.env.PLAY_RTDN_SECRET,
  supportEmail: process.env.SUPPORT_EMAIL,
  adminToken: process.env.ADMIN_TOKEN,
  trustProxy: process.env.TRUST_PROXY === "1",
  // Cloud Run: JSON lines Cloud Logging and Error Reporting understand.
  logger: process.env.NODE_ENV === "production" ? cloudLoggerOptions : true,
});
await app.listen({ port, host: "0.0.0.0" });

// Cloud Run sends SIGTERM before stopping an instance: finish requests, close the pool.
for (const signal of ["SIGTERM", "SIGINT"] as const) {
  process.once(signal, async () => {
    app.log.info({ signal }, "shutting down");
    await app.close();
    await db.close();
    process.exit(0);
  });
}
