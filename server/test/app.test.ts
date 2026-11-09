import { describe, expect, it } from "vitest";

import { buildApp } from "../src/app.js";
import type { ModelSegmenter } from "../src/segmentation/claudeSegmenter.js";
import { SegmentService } from "../src/segmentation/service.js";
import { MemoryQuotaStore, MemorySegmentCache, MemoryUsageLog } from "../src/stores/memory.js";
import { makeChapter, perfectOutput } from "./fixtures.js";

process.env.NODE_ENV = "test";

function app() {
  const model: ModelSegmenter = {
    segment: async (job) => ({ output: perfectOutput(job.chapter), model: job.route.model, inputTokens: 1, outputTokens: 1 }),
  };
  const quota = new MemoryQuotaStore();
  const segments = new SegmentService({ cache: new MemorySegmentCache(), quota, usage: new MemoryUsageLog(), model });
  return buildApp({ segments, quota });
}

const device = { "x-device-id": "abcdef0123456789" };
const body = (tier = "plus") => ({
  book: { content_hash: "a".repeat(64), title: "T", author: "A" },
  tier,
  chapters: [makeChapter(0)],
});

describe("HTTP API", () => {
  it("requires a device id and validates payloads", async () => {
    const a = app();
    expect((await a.inject({ method: "POST", url: "/v1/segment", payload: body() })).statusCode).toBe(401);
    const bad = await a.inject({ method: "POST", url: "/v1/segment", headers: device, payload: { tier: "plus" } });
    expect(bad.statusCode).toBe(400);
    const free = await a.inject({ method: "POST", url: "/v1/segment", headers: device, payload: body("free") });
    expect(free.statusCode).toBe(403);
  });

  it("segments chapters in the format the app expects", async () => {
    const res = await app().inject({ method: "POST", url: "/v1/segment", headers: device, payload: body() });
    expect(res.statusCode).toBe(200);
    const json = res.json();
    expect(json.chapters[0].source).toBe("ai");
    expect(json.chapters[0].cards[0]).toMatchObject({ start_sid: "c0.b0.s0", end_sid: "c0.b1.s3", key_sids: ["c0.b0.s1"] });
    expect(json.quota).toEqual({ used: 1, limit: 20 });
  });

  it("tracks reading, streaks and the weekly league", async () => {
    const a = app();
    await a.inject({ method: "PUT", url: "/v1/me/profile", headers: device, payload: { display_name: "Asha", daily_goal_cards: 2 } });
    const now = new Date().toISOString();
    const res = await a.inject({
      method: "POST",
      url: "/v1/activity/batch",
      headers: device,
      payload: {
        events: [
          { book_id: "b", card_ref: "c1", words: 120, dwell_ms: 30000, ts: now },
          { book_id: "b", card_ref: "c2", words: 120, dwell_ms: 30000, ts: now },
        ],
      },
    });
    expect(res.json()).toMatchObject({ accepted: 2, verified: 2, streak: 1 });
    expect((await a.inject({ url: "/v1/me/streak", headers: device })).json().current).toBe(1);
    const league = (await a.inject({ url: "/v1/leagues/current", headers: device })).json();
    expect(league.division).toBe("Bronze");
    expect(league.rows[0].name).toBe("Asha");
  });
});
