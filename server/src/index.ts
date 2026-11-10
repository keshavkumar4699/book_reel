import Anthropic from "@anthropic-ai/sdk";

import { buildApp } from "./app.js";
import { Authenticator, FirebaseVerifier } from "./auth.js";
import { openDb } from "./db/db.js";
import { loadCatalog } from "./music/catalog.js";
import { AnthropicBatchClient } from "./segmentation/batch.js";
import { ClaudeSegmenter } from "./segmentation/claudeSegmenter.js";
import { SegmentService } from "./segmentation/service.js";
import { SqlJobStore, SqlQuotaStore, SqlSegmentCache, SqlUsageLog } from "./stores/sql.js";

/**
 * Configuration (all optional for local development):
 * - DATABASE_URL         postgres://… for Postgres; otherwise a PGlite data dir (default ./data/pglite)
 * - ANTHROPIC_API_KEY    Claude credentials (or an `ant auth login` profile)
 * - FIREBASE_PROJECT_ID  enables Google sign-in (Firebase ID tokens)
 * - PUBLIC_BASE_URL      base for share/invite links (default http://localhost:PORT)
 * - ANDROID_CERT_SHA256  comma-separated signing-cert fingerprints for App Links
 * - MUSIC_CATALOG        soundtrack catalog JSON (default ./music/catalog.json); see music/catalog.example.json
 */
const port = Number(process.env.PORT ?? 8787);
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
const music = loadCatalog(process.env.MUSIC_CATALOG ?? "./music/catalog.json");
for (const e of music.errors) console.warn(`music catalog: ${e}`);
const projectId = process.env.FIREBASE_PROJECT_ID;
const app = buildApp({
  db,
  segments,
  quota,
  auth: new Authenticator(db, projectId ? new FirebaseVerifier(projectId) : undefined),
  publicBaseUrl: process.env.PUBLIC_BASE_URL ?? `http://localhost:${port}`,
  androidCertFingerprints: process.env.ANDROID_CERT_SHA256?.split(",").map((s) => s.trim()).filter(Boolean),
  music: music.tracks,
  logger: true,
});
await app.listen({ port, host: "0.0.0.0" });
