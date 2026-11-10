import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { buildApp } from "../src/app.js";
import type { Db } from "../src/db/db.js";
import { ModelRefusal, type ModelSegmenter } from "../src/segmentation/claudeSegmenter.js";
import { SegmentService } from "../src/segmentation/service.js";
import { SqlQuotaStore, SqlSegmentCache, SqlUsageLog } from "../src/stores/sql.js";
import { BookProfiler, ClaudeVoiceChooser, ruleVoice, type BookProfileRequest, type VoiceChooser } from "../src/typography/profile.js";
import { testDb } from "./helpers.js";

const req = (subjects: string[] = [], hash = "h".repeat(64)): BookProfileRequest => ({
  tier: "plus",
  book: { title: "The Silent Case", author: "A. Writer", content_hash: hash },
  subjects,
  sample: "The inspector knelt beside the body.",
});

describe("book typography profile", () => {
  it("rules read subject tags, children's books first", () => {
    expect(ruleVoice(req(["Detective and mystery stories"]))).toBe("suspense");
    expect(ruleVoice(req(["Fantasy fiction", "Children's stories"]))).toBe("playful");
    expect(ruleVoice(req(["Science fiction"]))).toBe("scifi");
    expect(ruleVoice(req(["Self-help techniques"]))).toBe("modern");
    expect(ruleVoice(req([]))).toBe("classic");
  });

  it("uses the AI's choice once per book and falls back to rules without caching failures", async () => {
    let calls = 0;
    const ok: VoiceChooser = {
      choose: async () => {
        calls++;
        return { voice: "suspense", genre: "police procedural" };
      },
    };
    const profiler = new BookProfiler(ok);
    expect(await profiler.profile(req())).toEqual({ voice: "suspense", genre: "police procedural", source: "ai" });
    await profiler.profile(req());
    expect(calls).toBe(1);

    let attempts = 0;
    const flaky = new BookProfiler({
      choose: async () => {
        attempts++;
        throw new ModelRefusal("no");
      },
    });
    expect((await flaky.profile(req(["Science fiction"]))).source).toBe("rules");
    expect((await flaky.profile(req(["Science fiction"]))).voice).toBe("scifi");
    expect(attempts).toBe(2); // not cached, so a later request can try the AI again
  });

  it("asks Claude with a voice enum, effort and the opening sample", async () => {
    let params: Record<string, unknown> | undefined;
    const client = {
      messages: {
        stream: (p: Record<string, unknown>) => {
          params = p;
          return {
            finalMessage: async () => ({
              stop_reason: "end_turn",
              content: [{ type: "text", text: JSON.stringify({ genre: "space opera", voice: "scifi" }) }],
            }),
          };
        },
      },
    };
    const out = await new ClaudeVoiceChooser(client as never).choose(req(["Science fiction"]));
    expect(out).toEqual({ voice: "scifi", genre: "space opera" });
    expect(params?.model).toBe("claude-haiku-5-5");
    const config = params?.output_config as { effort: string; format: { schema: { properties: { voice: { enum: string[] } } } } };
    expect(config.effort).toBe("low");
    expect(config.format.schema.properties.voice.enum).toContain("playful");
    expect(JSON.stringify(params?.messages)).toContain("The inspector knelt");
  });

  it("treats a refusal as unavailable", async () => {
    const client = { messages: { stream: () => ({ finalMessage: async () => ({ stop_reason: "refusal", content: [] }) }) } };
    await expect(new ClaudeVoiceChooser(client as never).choose(req())).rejects.toBeInstanceOf(ModelRefusal);
  });
});

describe("POST /v1/book/profile", () => {
  let db: Db;
  beforeEach(async () => {
    db = await testDb();
  });
  afterEach(() => db.close());

  it("is for paid tiers and validates the request", async () => {
    const model: ModelSegmenter = {
      structure: async () => {
        throw new Error("unused");
      },
      present: async () => {
        throw new Error("unused");
      },
    };
    const quota = new SqlQuotaStore(db);
    const segments = new SegmentService({ cache: new SqlSegmentCache(db), quota, usage: new SqlUsageLog(db), model });
    const app = buildApp({ db, segments, quota, voiceChooser: { choose: async () => ({ voice: "romance", genre: "regency romance" }) } });
    const headers = { "x-device-id": "abcdef0123456789" };
    const payload = { ...req(), tier: "free" };
    expect((await app.inject({ method: "POST", url: "/v1/book/profile", headers, payload })).statusCode).toBe(403);
    const ok = await app.inject({ method: "POST", url: "/v1/book/profile", headers, payload: req() });
    expect(ok.statusCode).toBe(200);
    expect(ok.json()).toEqual({ voice: "romance", genre: "regency romance", source: "ai" });
    const bad = await app.inject({ method: "POST", url: "/v1/book/profile", headers, payload: { tier: "plus", book: { title: "x" } } });
    expect(bad.statusCode).toBe(400);
  });
});
