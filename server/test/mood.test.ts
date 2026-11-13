import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { buildApp } from "../src/app.js";
import type { Db } from "../src/db/db.js";
import {
  buildMoodPrompt,
  DAILY_MOOD_CALLS,
  MOOD_SYSTEM,
  MoodService,
  moodModelFromEnv,
  OpenAICompatibleChat,
  parseMoodReply,
  slotOf,
  type MoodModel,
} from "../src/mood/suggest.js";
import { SegmentService } from "../src/segmentation/service.js";
import { SqlJobStore, SqlQuotaStore, SqlSegmentCache, SqlUsageLog } from "../src/stores/sql.js";
import { testDb } from "./helpers.js";

let db: Db;
beforeEach(async () => {
  db = await testDb();
});
afterEach(() => db.close());

class FakeGemma implements MoodModel {
  readonly id = "fake|gemma";
  prompts: string[] = [];
  constructor(private readonly reply: string) {}
  async complete(system: string, prompt: string) {
    expect(system).toBe(MOOD_SYSTEM);
    this.prompts.push(prompt);
    return this.reply;
  }
}

function app(mood?: MoodService) {
  const quota = new SqlQuotaStore(db);
  const segments = new SegmentService({
    cache: new SqlSegmentCache(db),
    quota,
    usage: new SqlUsageLog(db),
    jobs: new SqlJobStore(db),
    model: { structure: async () => { throw new Error("unused"); }, present: async () => { throw new Error("unused"); } },
  });
  return buildApp({ db, segments, quota, mood });
}

const device = { "x-device-id": "abcdef0123456789" };
const log = [
  { weekday: 2, hour: 21, mood: "cozy", minutes: 34, days_ago: 0, source: "asked" },
  { weekday: 1, hour: 21, mood: "cozy", minutes: 20, days_ago: 1, source: "asked" },
  { weekday: 1, hour: 8, mood: "focused", minutes: 15, days_ago: 1, source: "corrected" },
  { weekday: 6, hour: 15, mood: "energised", minutes: 40, days_ago: 3, source: "asked" },
  { weekday: 3, hour: 21, mood: "calm", minutes: 5, days_ago: 90, source: "asked" },
];
const ask = (a: ReturnType<typeof app>, payload: Record<string, unknown>) => a.inject({ method: "POST", url: "/v1/mood/suggest", headers: device, payload });

describe("mood suggestions", () => {
  it("asks Gemma with the mood log only and returns its mood", async () => {
    const gemma = new FakeGemma('Sure! {"mood": "Cozy", "reason": "Weekday evenings are usually cozy for you."}');
    const res = await ask(app(new MoodService(db, gemma)), { now: { weekday: 3, hour: 21 }, log });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ mood: "cozy", reason: "Weekday evenings are usually cozy for you." });
    const prompt = gemma.prompts[0]!;
    expect(prompt).toContain("Now: Wed 21:00 (weekday evening).");
    expect(prompt).toContain("- weekday evening: cozy 2");
    expect(prompt).toContain("- weekday morning: focused 2"); // a correction counts double
    expect(prompt).toContain("- Tue 21:00 cozy, 34 min");
    expect(prompt).not.toContain("calm"); // older than 60 days
  });

  it("refuses anything but the mood log", async () => {
    const a = app(new MoodService(db, new FakeGemma('{"mood":"calm"}')));
    expect((await ask(a, { now: { weekday: 3, hour: 21 }, log, book: "Alice in Wonderland" })).statusCode).toBe(400);
    expect((await ask(a, { now: { weekday: 3, hour: 21 }, log: [{ ...log[0], text: "a quote" }] })).statusCode).toBe(400);
    expect((await ask(a, { now: { weekday: 3, hour: 21 }, log: [{ ...log[0], mood: "angry" }] })).statusCode).toBe(400);
    expect((await ask(a, { now: { weekday: 8, hour: 21 }, log })).statusCode).toBe(400);
    expect((await ask(a, { now: { weekday: 3, hour: 21 }, log: Array(201).fill(log[0]) })).statusCode).toBe(400);
  });

  it("a reply that is not one of the moods is refused (502)", async () => {
    for (const reply of ['{"mood": "happy", "reason": "x"}', "I think you would enjoy something calm and cozy.", "{not json}"]) {
      const res = await ask(app(new MoodService(db, new FakeGemma(reply))), { now: { weekday: 3, hour: 21 }, log });
      expect(res.statusCode, reply).toBe(502);
      expect(res.json().error).toBe("mood_invalid");
    }
  });

  it("without a model the app is told to predict on its own (503)", async () => {
    const res = await ask(app(), { now: { weekday: 3, hour: 21 }, log });
    expect(res.statusCode).toBe(503);
    expect(res.json().error).toBe("mood_unavailable");
  });

  it("caps suggestions per reader per day (429)", async () => {
    const a = app(new MoodService(db, new FakeGemma('{"mood":"calm","reason":""}')));
    for (let i = 0; i < DAILY_MOOD_CALLS; i++) {
      expect((await ask(a, { now: { weekday: 3, hour: 21 }, log: [] })).statusCode).toBe(200);
    }
    const over = await ask(a, { now: { weekday: 3, hour: 21 }, log: [] });
    expect(over.statusCode).toBe(429);
    expect(over.json()).toEqual({ error: "mood_quota", limit: DAILY_MOOD_CALLS });
  });

  it("parses replies and names the time of day", () => {
    expect(parseMoodReply('{"mood":"energized","reason":"  Saturday\\nafternoons  "}')).toEqual({ mood: "energised", reason: "Saturday afternoons" });
    expect(parseMoodReply("cosy.")).toEqual({ mood: "cozy", reason: "" });
    expect(parseMoodReply("")).toBeNull();
    expect([4, 5, 11, 12, 16, 17, 21, 22].map(slotOf)).toEqual([
      "night", "morning", "morning", "afternoon", "afternoon", "evening", "evening", "night",
    ]);
    expect(buildMoodPrompt([], { weekday: 7, hour: 9 })).toContain("Now: Sun 09:00 (weekend morning).\n");
  });

  it("calls an OpenAI-compatible chat endpoint (DeepInfra by default)", async () => {
    const calls: { url: string; body: { model: string; messages: { role: string; content: string }[] } }[] = [];
    const fetchImpl = (async (url: string, init: RequestInit) => {
      calls.push({ url, body: JSON.parse(String(init.body)) });
      return new Response(JSON.stringify({ choices: [{ message: { content: '{"mood":"dreamy","reason":"late nights"}' } }] }));
    }) as unknown as typeof fetch;
    const chat = new OpenAICompatibleChat({ baseUrl: "https://example.test/v1/", apiKey: "k", model: "google/gemma-3-12b-it", fetchImpl });
    expect(await chat.complete("SYSTEM", "PROMPT")).toBe('{"mood":"dreamy","reason":"late nights"}');
    expect(calls[0]!.url).toBe("https://example.test/v1/chat/completions");
    expect(calls[0]!.body.model).toBe("google/gemma-3-12b-it");
    expect(calls[0]!.body.messages).toEqual([{ role: "user", content: "SYSTEM\n\nPROMPT" }]);

    const down = new OpenAICompatibleChat({ baseUrl: "https://x", apiKey: "k", model: "m", fetchImpl: (async () => new Response("", { status: 500 })) as unknown as typeof fetch });
    await expect(down.complete("s", "p")).rejects.toThrow("answered 500");

    expect(moodModelFromEnv({})).toBeUndefined();
    expect(moodModelFromEnv({ TTS_API_KEY: "k" })?.id).toBe("https://api.deepinfra.com/v1/openai|google/gemma-3-12b-it");
    expect(moodModelFromEnv({ MOOD_API_KEY: "k", MOOD_MODEL: "google/gemma-3-4b-it", MOOD_BASE_URL: "https://h/v1" })?.id).toBe("https://h/v1|google/gemma-3-4b-it");
  });
});
