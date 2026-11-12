import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { buildApp } from "../src/app.js";
import type { Db } from "../src/db/db.js";
import type { ModelSegmenter } from "../src/segmentation/claudeSegmenter.js";
import { SegmentService } from "../src/segmentation/service.js";
import { SqlJobStore, SqlQuotaStore, SqlSegmentCache, SqlUsageLog } from "../src/stores/sql.js";
import { makeChapter, presentationOutput, structureOutput } from "./fixtures.js";
import { testDb } from "./helpers.js";

let db: Db;
beforeEach(async () => {
  db = await testDb();
});
afterEach(() => db.close());

function app() {
  const model: ModelSegmenter = {
    structure: async (job) => ({ output: structureOutput(job.chapter), model: job.route.model, inputTokens: 1, outputTokens: 1 }),
    present: async (job) => ({ output: presentationOutput(job.cards), model: "claude-haiku-5-5", inputTokens: 1, outputTokens: 1 }),
  };
  const quota = new SqlQuotaStore(db);
  const segments = new SegmentService({
    cache: new SqlSegmentCache(db),
    quota,
    usage: new SqlUsageLog(db),
    jobs: new SqlJobStore(db),
    model,
  });
  return buildApp({ db, segments, quota, publicBaseUrl: "https://bookreel.app", androidCertFingerprints: ["AA:BB"] });
}

const device = { "x-device-id": "abcdef0123456789" };
const friend = { "x-device-id": "0123456789abcdef" };
const body = (tier = "lite") => ({
  book: { content_hash: "a".repeat(64), title: "T", author: "A" },
  tier,
  card_length: "standard",
  chapters: [makeChapter(0)],
});

describe("HTTP API", () => {
  it("requires credentials and validates payloads", async () => {
    const a = app();
    expect((await a.inject({ method: "POST", url: "/v1/segment", payload: body() })).statusCode).toBe(401);
    expect((await a.inject({ method: "POST", url: "/v1/segment", headers: device, payload: { tier: "lite" } })).statusCode).toBe(400);
    expect((await a.inject({ method: "POST", url: "/v1/segment", headers: device, payload: body("free") })).statusCode).toBe(403);
  });

  it("segments chapters in the format the app expects and caches them in Postgres", async () => {
    const a = app();
    const res = await a.inject({ method: "POST", url: "/v1/segment", headers: device, payload: body() });
    expect(res.statusCode).toBe(200);
    const json = res.json();
    expect(json.chapters[0].cards[0]).toMatchObject({
      start_sid: "c0.b0.s0",
      end_sid: "c0.b1.s3",
      key_sids: ["c0.b0.s0"],
      layout: "centered",
      emphasis: [{ sid: "c0.b0.s0", text: "quiet power", level: 3 }],
    });
    expect(json.chapters[0]).toMatchObject({ scene: "forest", scene_cues: [] });
    expect(json.chapters[0].music_cues).toBeUndefined();
    expect(json.chapters[0].cards[0].mood).toBeUndefined();
    expect(json.quota).toEqual({ used: 1, limit: 12 });
    const again = (await a.inject({ method: "POST", url: "/v1/segment", headers: device, payload: body() })).json();
    expect(again.cached).toBe(1);
  });

  it("AI usage reports each tier's monthly book limit", async () => {
    const a = app();
    const usage = async (q: string) => (await a.inject({ url: `/v1/me/ai-usage${q}`, headers: device })).json();
    expect(await usage("")).toMatchObject({ books_used: 0, books_limit: 12 }); // Lite by default
    expect((await usage("?tier=plus")).books_limit).toBe(6);
    expect((await usage("?tier=scholar")).books_limit).toBe(6);
    expect((await usage("?tier=gold")).books_limit).toBe(12); // unknown tiers read as Lite, never crash
  });

  it("profile: username (unique, any case), pronouns, bio and avatar emoji", async () => {
    const a = app();
    const put = (headers: Record<string, string>, payload: object) => a.inject({ method: "PUT", url: "/v1/me/profile", headers, payload });
    const res = await put(device, { display_name: "Asha", handle: "@Asha.Reads", pronouns: "she/her", bio: "Classics on the commute.  ", avatar: "🦉" });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ handle: "asha.reads", pronouns: "she/her", bio: "Classics on the commute.", avatar: "🦉" });
    expect((await a.inject({ url: "/v1/me", headers: device })).json()).toMatchObject({ display_name: "Asha", handle: "asha.reads", bio: "Classics on the commute." });
    // Someone else cannot take it, in any letter case; a bad name is refused.
    expect((await put(friend, { handle: "ASHA.reads" })).statusCode).toBe(409);
    expect((await put(friend, { handle: "no spaces!" })).statusCode).toBe(400);
    expect((await put(friend, { handle: "ravi_99" })).statusCode).toBe(200);
    // Keeping your own name, or changing only the bio, is fine.
    expect((await put(device, { handle: "asha.reads", bio: "" })).json()).toMatchObject({ handle: "asha.reads", bio: "" });
    // An empty username clears it and frees it.
    expect((await put(device, { handle: "" })).json().handle).toBeNull();
    expect((await put(friend, { handle: "asha.reads" })).statusCode).toBe(200);
  });

  it("friends: invite code, activity, league, friends board, feed and kudos", async () => {
    const a = app();
    await a.inject({ method: "PUT", url: "/v1/me/profile", headers: device, payload: { display_name: "Asha", daily_goal_cards: 2 } });
    const me = (await a.inject({ url: "/v1/me", headers: device })).json();
    expect(me).toMatchObject({ display_name: "Asha", signed_in: false });
    expect(me.invite_url).toBe(`https://bookreel.app/i/${me.invite_code}`);

    const added = await a.inject({ method: "POST", url: "/v1/social/follow-code", headers: friend, payload: { code: me.invite_code } });
    expect(added.json().friend.name).toBe("Asha");
    expect((await a.inject({ method: "POST", url: "/v1/social/follow-code", headers: friend, payload: { code: "XXXX" } })).statusCode).toBe(404);

    const now = new Date().toISOString();
    const res = await a.inject({
      method: "POST",
      url: "/v1/activity/batch",
      headers: device,
      payload: { events: [1, 2].map((i) => ({ book_id: "b", card_ref: `c${i}`, words: 120, dwell_ms: 30000, ts: now })) },
    });
    expect(res.json()).toMatchObject({ accepted: 2, verified: 2, streak: 1 });
    expect((await a.inject({ url: "/v1/me/streak", headers: device })).json().current).toBe(1);
    expect((await a.inject({ url: "/v1/leagues/current", headers: device })).json().division).toBe("Bronze");

    const board = (await a.inject({ url: "/v1/leaderboards/friends", headers: friend })).json();
    expect(board.rows[0]).toMatchObject({ name: "Asha", activeDays: 1 });
    const feed = (await a.inject({ url: "/v1/feed", headers: friend })).json().items;
    expect(feed[0].text).toContain("Asha");
    expect((await a.inject({ method: "POST", url: `/v1/activities/${feed[0].id}/kudos`, headers: friend })).statusCode).toBe(200);
  });

  it("sync, share links, invite page and App Links", async () => {
    const a = app();
    const push = await a.inject({
      method: "PUT",
      url: "/v1/sync",
      headers: device,
      payload: { items: [{ kind: "saved", id: "s1", updated_at: 10, data: { text: "hi" } }] },
    });
    expect(push.json().applied).toBe(1);
    expect((await a.inject({ url: "/v1/sync?since=0", headers: device })).json().items).toHaveLength(1);
    expect((await a.inject({ url: "/v1/sync?since=0", headers: friend })).json().items).toHaveLength(0);

    const share = (
      await a.inject({ method: "POST", url: "/v1/share", headers: device, payload: { type: "progress", headline: "7-day streak", lines: ["70 cards"] } })
    ).json();
    const page = await a.inject({ url: new URL(share.url).pathname });
    expect(page.headers["content-type"]).toContain("text/html");
    expect(page.body).toContain("7-day streak");
    expect((await a.inject({ url: "/c/nope" })).statusCode).toBe(404);
    expect((await a.inject({ url: "/i/abc<script>" })).body).toContain("ABCSCRIPT");
    expect((await a.inject({ url: "/.well-known/assetlinks.json" })).json()[0].target.sha256_cert_fingerprints).toEqual(["AA:BB"]);
  });
});
