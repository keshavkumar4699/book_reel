import { createHash } from "node:crypto";

import { z } from "zod";

import { isPaidTier } from "../config.js";
import type { Db } from "../db/db.js";

/**
 * Natural read-aloud voice (DESIGN.md §2.4): the app sends the words of a
 * reel, the server returns MP3 audio from a neural TTS model. The default is
 * Kokoro-82M (Apache-2.0) on a hosted GPU API through the widely supported
 * OpenAI-style `POST /audio/speech` endpoint, so the provider can be swapped
 * (OpenAI, a self-hosted Kokoro server…) with configuration only.
 *
 * Audio is cached by its text and voice, so a passage is synthesised once
 * and replayed for free (popular public-domain books once for everyone).
 */

/** Voices offered in the app (Kokoro voice names). */
export const SPEECH_VOICES = ["af_heart", "am_michael", "bf_emma", "bm_george"] as const;
export type SpeechVoice = (typeof SPEECH_VOICES)[number];

export const SpeechRequestSchema = z.object({
  text: z.string().trim().min(1).max(1500),
  voice: z.enum(SPEECH_VOICES).default("af_heart"),
  speed: z.number().min(0.7).max(1.4).default(1),
  tier: z.string().default("free"),
});
export type SpeechRequest = z.infer<typeof SpeechRequestSchema>;

/**
 * Characters a reader may synthesise per day. Generous for paid plans
 * (about 6 hours of listening); a taste for Free. Replays from the cache
 * don't count. At ~$1 per million characters even the paid cap costs
 * about $0.30 a day at most.
 */
export const DAILY_SPEECH_CHARS = { free: 20_000, paid: 300_000 } as const;

export interface SpeechAudio {
  audio: Buffer;
  /** e.g. "audio/mpeg" */
  contentType: string;
}

export interface SpeechProvider {
  readonly id: string;
  synthesize(text: string, voice: SpeechVoice, speed: number): Promise<SpeechAudio>;
}

export class SpeechUnavailable extends Error {}
export class SpeechQuotaExceeded extends Error {
  constructor(readonly limit: number) {
    super(`Daily read-aloud limit reached (${limit} characters)`);
  }
}

/** Any OpenAI-compatible speech endpoint (DeepInfra, OpenAI, Kokoro-FastAPI…). */
export class OpenAICompatibleSpeech implements SpeechProvider {
  constructor(
    private readonly opts: { baseUrl: string; apiKey: string; model: string; fetchImpl?: typeof fetch; timeoutMs?: number },
  ) {}

  get id() {
    return `${this.opts.baseUrl}|${this.opts.model}`;
  }

  async synthesize(text: string, voice: SpeechVoice, speed: number): Promise<SpeechAudio> {
    const res = await (this.opts.fetchImpl ?? fetch)(`${this.opts.baseUrl.replace(/\/$/, "")}/audio/speech`, {
      method: "POST",
      headers: { authorization: `Bearer ${this.opts.apiKey}`, "content-type": "application/json" },
      body: JSON.stringify({ model: this.opts.model, input: text, voice, speed, response_format: "mp3" }),
      signal: AbortSignal.timeout(this.opts.timeoutMs ?? 20_000),
    });
    if (!res.ok) throw new SpeechUnavailable(`speech provider answered ${res.status}`);
    const audio = Buffer.from(await res.arrayBuffer());
    if (audio.length < 64) throw new SpeechUnavailable("speech provider returned no audio");
    return { audio, contentType: res.headers.get("content-type")?.startsWith("audio/") ? res.headers.get("content-type")! : "audio/mpeg" };
  }
}

/** The provider from the environment, or none (the app then uses the phone's voice). */
export function speechProviderFromEnv(env: NodeJS.ProcessEnv = process.env): SpeechProvider | undefined {
  const apiKey = env.TTS_API_KEY;
  if (!apiKey) return undefined;
  return new OpenAICompatibleSpeech({
    baseUrl: env.TTS_BASE_URL ?? "https://api.deepinfra.com/v1/openai",
    model: env.TTS_MODEL ?? "hexgrad/Kokoro-82M",
    apiKey,
  });
}

export class SpeechService {
  constructor(
    private readonly db: Db,
    private readonly provider: SpeechProvider,
    private readonly clock: () => Date = () => new Date(),
  ) {}

  static cacheKey(providerId: string, req: Pick<SpeechRequest, "text" | "voice" | "speed">): string {
    return createHash("sha256").update(`${providerId}\n${req.voice}\n${req.speed.toFixed(2)}\n${req.text}`).digest("hex");
  }

  async speak(userId: string, req: SpeechRequest): Promise<SpeechAudio & { cached: boolean }> {
    const key = SpeechService.cacheKey(this.provider.id, req);
    const hit = await this.db.query<{ audio: Uint8Array; content_type: string }>(`select audio, content_type from tts_cache where key = $1`, [key]);
    if (hit[0]) return { audio: Buffer.from(hit[0].audio), contentType: hit[0].content_type, cached: true };

    const day = this.clock().toISOString().slice(0, 10);
    const limit = isPaidTier(req.tier) ? DAILY_SPEECH_CHARS.paid : DAILY_SPEECH_CHARS.free;
    const used = await this.db.query<{ chars: number }>(`select chars from tts_usage where user_id = $1 and day = $2`, [userId, day]);
    if ((used[0]?.chars ?? 0) + req.text.length > limit) throw new SpeechQuotaExceeded(limit);

    const out = await this.provider.synthesize(req.text, req.voice, req.speed);
    await this.db.query(
      `insert into tts_usage (user_id, day, chars) values ($1, $2, $3)
       on conflict (user_id, day) do update set chars = tts_usage.chars + excluded.chars`,
      [userId, day, req.text.length],
    );
    await this.db.query(
      `insert into tts_cache (key, content_type, audio, chars) values ($1, $2, $3, $4) on conflict (key) do nothing`,
      [key, out.contentType, out.audio, req.text.length],
    );
    return { ...out, cached: false };
  }
}
