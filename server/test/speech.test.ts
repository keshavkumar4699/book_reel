import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { buildApp } from "../src/app.js";
import type { Db } from "../src/db/db.js";
import { SegmentService } from "../src/segmentation/service.js";
import {
  OpenAICompatibleSpeech,
  SpeechService,
  speechProviderFromEnv,
  type SpeechProvider,
  type SpeechVoice,
} from "../src/speech/tts.js";
import { SqlJobStore, SqlQuotaStore, SqlSegmentCache, SqlUsageLog } from "../src/stores/sql.js";
import { testDb } from "./helpers.js";

let db: Db;
beforeEach(async () => {
  db = await testDb();
});
afterEach(() => db.close());

class FakeProvider implements SpeechProvider {
  readonly id = "fake|kokoro";
  calls: { text: string; voice: SpeechVoice; speed: number }[] = [];
  async synthesize(text: string, voice: SpeechVoice, speed: number) {
    this.calls.push({ text, voice, speed });
    return { audio: Buffer.from(`ID3 mp3 of ${voice}: ${text}`.padEnd(80, ".")), contentType: "audio/mpeg" };
  }
}

function app(speech?: SpeechService) {
  const quota = new SqlQuotaStore(db);
  const segments = new SegmentService({
    cache: new SqlSegmentCache(db),
    quota,
    usage: new SqlUsageLog(db),
    jobs: new SqlJobStore(db),
    model: { structure: async () => { throw new Error("unused"); }, present: async () => { throw new Error("unused"); } },
  });
  return buildApp({ db, segments, quota, speech });
}

const device = { "x-device-id": "abcdef0123456789" };

describe("read aloud", () => {
  it("returns MP3 audio and synthesises each passage once", async () => {
    const provider = new FakeProvider();
    const a = app(new SpeechService(db, provider));
    const ask = () => a.inject({ method: "POST", url: "/v1/tts", headers: device, payload: { text: "Alice was beginning to get very tired.", voice: "bf_emma" } });
    const first = await ask();
    expect(first.statusCode).toBe(200);
    expect(first.headers["content-type"]).toBe("audio/mpeg");
    expect(first.headers["x-cache"]).toBe("miss");
    expect(first.rawPayload.toString()).toContain("mp3 of bf_emma: Alice was beginning");
    const again = await ask();
    expect(again.headers["x-cache"]).toBe("hit");
    expect(again.rawPayload.equals(first.rawPayload)).toBe(true);
    expect(provider.calls).toHaveLength(1);
    // A different voice or speed is a different recording.
    await a.inject({ method: "POST", url: "/v1/tts", headers: device, payload: { text: "Alice was beginning to get very tired.", voice: "bf_emma", speed: 1.2 } });
    expect(provider.calls.map((c) => c.speed)).toEqual([1, 1.2]);
  });

  it("only offered voices, sensible lengths, and a daily allowance per plan", async () => {
    const provider = new FakeProvider();
    let now = new Date("2026-11-12T10:00:00Z");
    const a = app(new SpeechService(db, provider, () => now));
    const say = (payload: object) => a.inject({ method: "POST", url: "/v1/tts", headers: device, payload });
    expect((await say({ text: "Hi", voice: "darth_vader" })).statusCode).toBe(400);
    expect((await say({ text: "x".repeat(1501) })).statusCode).toBe(400);
    expect((await say({ text: "   " })).statusCode).toBe(400);
    // Free: 20,000 characters a day.
    const long = "word ".repeat(300).trim(); // ~1,500 characters
    let ok = 0;
    for (let i = 0; i < 20; i++) {
      const r = await say({ text: `${i} ${long}`.slice(0, 1500) });
      if (r.statusCode === 200) ok++;
      else expect(r.json()).toMatchObject({ error: "speech_quota", limit: 20_000 });
    }
    expect(ok).toBe(13);
    // Replays from the cache are always free; paid plans get far more; a new day resets.
    expect((await say({ text: `0 ${long}`.slice(0, 1500) })).statusCode).toBe(200);
    expect((await say({ text: `new ${long}`.slice(0, 1500), tier: "lite" })).statusCode).toBe(200);
    now = new Date("2026-11-13T10:00:00Z");
    expect((await say({ text: `tomorrow ${long}`.slice(0, 1500) })).statusCode).toBe(200);
  });

  it("without a provider the app is told to use the phone voice", async () => {
    const res = await app().inject({ method: "POST", url: "/v1/tts", headers: device, payload: { text: "Hello there." } });
    expect(res.statusCode).toBe(503);
    expect(res.json().error).toBe("tts_unavailable");
    expect(speechProviderFromEnv({})).toBeUndefined();
    expect(speechProviderFromEnv({ TTS_API_KEY: "k" })?.id).toBe("https://api.deepinfra.com/v1/openai|hexgrad/Kokoro-82M");
  });

  it("speaks the OpenAI-compatible speech API", async () => {
    const seen: { url: string; init: RequestInit }[] = [];
    const fetchImpl = (async (url: string, init: RequestInit) => {
      seen.push({ url, init });
      return new Response(new Uint8Array(200).fill(7), { status: 200, headers: { "content-type": "audio/mpeg" } });
    }) as unknown as typeof fetch;
    const p = new OpenAICompatibleSpeech({ baseUrl: "https://tts.example/v1/", apiKey: "secret", model: "hexgrad/Kokoro-82M", fetchImpl });
    const out = await p.synthesize("Down the rabbit hole.", "am_michael", 1.1);
    expect(out.audio).toHaveLength(200);
    expect(seen[0]!.url).toBe("https://tts.example/v1/audio/speech");
    expect((seen[0]!.init.headers as Record<string, string>).authorization).toBe("Bearer secret");
    expect(JSON.parse(seen[0]!.init.body as string)).toEqual({
      model: "hexgrad/Kokoro-82M",
      input: "Down the rabbit hole.",
      voice: "am_michael",
      speed: 1.1,
      response_format: "mp3",
    });
    const failing = new OpenAICompatibleSpeech({
      baseUrl: "https://tts.example/v1",
      apiKey: "k",
      model: "m",
      fetchImpl: (async () => new Response("nope", { status: 500 })) as unknown as typeof fetch,
    });
    await expect(failing.synthesize("x", "af_heart", 1)).rejects.toThrow("speech provider answered 500");
  });
});
