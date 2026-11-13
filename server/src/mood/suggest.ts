import { z } from "zod";

import type { Db } from "../db/db.js";

/**
 * Mood suggestions (Cloro plan §8): the app learns how a reader usually feels
 * when they read (asked "How are you feeling?" while learning), then asks
 * Google's Gemma which mood suits them right now, and opens the book in that
 * mood's scene.
 *
 * Only the mood log is sent: weekday, hour, mood, minutes read and how long
 * ago. No book text, no names. The request schema is strict, so nothing else
 * can ride along. The model runs behind any OpenAI-compatible chat endpoint
 * (DeepInfra by default, the same provider as the read-aloud voice).
 *
 * The app keeps a copy of the prompt and parser (app/lib/services/mood.dart)
 * for the on-device Gemma; keep the two in step.
 */

export const MOODS = ["calm", "cozy", "focused", "energised", "dreamy", "reflective", "restless"] as const;
export type Mood = (typeof MOODS)[number];

const LogEntrySchema = z
  .object({
    /** ISO weekday: 1 = Monday … 7 = Sunday. */
    weekday: z.number().int().min(1).max(7),
    hour: z.number().int().min(0).max(23),
    mood: z.enum(MOODS),
    minutes: z.number().min(0).max(600).default(0),
    days_ago: z.number().int().min(0).max(366).default(0),
    source: z.enum(["asked", "corrected", "predicted"]).default("asked"),
  })
  .strict();
export type MoodLogEntry = z.infer<typeof LogEntrySchema>;

export const MoodSuggestSchema = z
  .object({
    now: z.object({ weekday: z.number().int().min(1).max(7), hour: z.number().int().min(0).max(23) }).strict(),
    log: z.array(LogEntrySchema).max(200),
    tier: z.string().max(20).default("free"),
  })
  .strict();
export type MoodSuggestRequest = z.infer<typeof MoodSuggestSchema>;

/** Suggestions a reader may ask for per day (the app asks about once per time of day). */
export const DAILY_MOOD_CALLS = 30;

export class MoodUnavailable extends Error {}
export class MoodInvalid extends Error {}
export class MoodQuotaExceeded extends Error {
  constructor(readonly limit: number) {
    super(`Daily mood suggestion limit reached (${limit})`);
  }
}

const DAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
const SLOTS = ["morning", "afternoon", "evening", "night"] as const;

/** Morning 5–12, afternoon 12–17, evening 17–22, night 22–5. */
export function slotOf(hour: number): (typeof SLOTS)[number] {
  if (hour >= 5 && hour < 12) return "morning";
  if (hour >= 12 && hour < 17) return "afternoon";
  if (hour >= 17 && hour < 22) return "evening";
  return "night";
}

const dayType = (weekday: number) => (weekday >= 6 ? "weekend" : "weekday");

export const MOOD_SYSTEM =
  "You suggest a reading mood for Cloro, a reading app. You get a summary of when one reader has read and how they felt. " +
  'Reply with JSON only: {"mood": "<calm|cozy|focused|energised|dreamy|reflective|restless>", "reason": "<at most 12 words>"}.';

/** The question for the model: counts by time of day, then recent sessions. */
export function buildMoodPrompt(log: MoodLogEntry[], now: { weekday: number; hour: number }): string {
  const recent = log.filter((e) => e.days_ago <= 60);
  const counts = new Map<string, Map<Mood, number>>();
  for (const e of recent) {
    if (e.source === "predicted") continue; // the reader's own answers only
    const key = `${dayType(e.weekday)} ${slotOf(e.hour)}`;
    const m = counts.get(key) ?? new Map<Mood, number>();
    m.set(e.mood, (m.get(e.mood) ?? 0) + (e.source === "corrected" ? 2 : 1));
    counts.set(key, m);
  }
  const lines: string[] = [];
  for (const d of ["weekday", "weekend"]) {
    for (const s of SLOTS) {
      const m = counts.get(`${d} ${s}`);
      if (!m) continue;
      const parts = [...m.entries()].sort((a, b) => b[1] - a[1]).map(([mood, n]) => `${mood} ${n}`);
      lines.push(`- ${d} ${s}: ${parts.join(", ")}`);
    }
  }
  const sessions = [...recent]
    .sort((a, b) => a.days_ago - b.days_ago)
    .slice(0, 12)
    .map((e) => `- ${DAYS[e.weekday - 1]} ${String(e.hour).padStart(2, "0")}:00 ${e.mood}, ${Math.round(e.minutes)} min`);
  return [
    `Now: ${DAYS[now.weekday - 1]} ${String(now.hour).padStart(2, "0")}:00 (${dayType(now.weekday)} ${slotOf(now.hour)}).`,
    "How they usually feel (answers in the last 60 days; corrections count double):",
    ...(lines.length ? lines : ["- no answers yet"]),
    "Recent sessions (newest first):",
    ...(sessions.length ? sessions : ["- none"]),
    "Which mood suits them right now?",
  ].join("\n");
}

/** The mood and reason from a model reply, or null when it isn't one of the moods. */
export function parseMoodReply(reply: string): { mood: Mood; reason: string } | null {
  const norm = (s: unknown) =>
    String(s ?? "")
      .trim()
      .toLowerCase()
      .replace(/^energized$/, "energised")
      .replace(/^cosy$/, "cozy");
  const json = reply.match(/\{[\s\S]*?\}/)?.[0];
  if (json) {
    try {
      const o = JSON.parse(json) as { mood?: unknown; reason?: unknown };
      const mood = norm(o.mood);
      if ((MOODS as readonly string[]).includes(mood)) {
        const reason = String(o.reason ?? "").replace(/\s+/g, " ").trim().slice(0, 120);
        return { mood: mood as Mood, reason };
      }
    } catch {
      /* not JSON after all */
    }
    return null;
  }
  // A bare word ("cozy") is fine too.
  const word = norm(reply.replace(/[^a-zA-Z]/g, ""));
  return (MOODS as readonly string[]).includes(word) ? { mood: word as Mood, reason: "" } : null;
}

export interface MoodModel {
  readonly id: string;
  complete(system: string, prompt: string): Promise<string>;
}

/** Any OpenAI-compatible chat endpoint (DeepInfra, a self-hosted vLLM…). */
export class OpenAICompatibleChat implements MoodModel {
  constructor(
    private readonly opts: { baseUrl: string; apiKey: string; model: string; fetchImpl?: typeof fetch; timeoutMs?: number },
  ) {}

  get id() {
    return `${this.opts.baseUrl}|${this.opts.model}`;
  }

  async complete(system: string, prompt: string): Promise<string> {
    let res: Response;
    try {
      res = await (this.opts.fetchImpl ?? fetch)(`${this.opts.baseUrl.replace(/\/$/, "")}/chat/completions`, {
        method: "POST",
        headers: { authorization: `Bearer ${this.opts.apiKey}`, "content-type": "application/json" },
        body: JSON.stringify({
          model: this.opts.model,
          // Gemma has no system role: the instructions open the user turn.
          messages: [{ role: "user", content: `${system}\n\n${prompt}` }],
          max_tokens: 80,
          temperature: 0.2,
        }),
        signal: AbortSignal.timeout(this.opts.timeoutMs ?? 10_000),
      });
    } catch (e) {
      throw new MoodUnavailable(`mood model unreachable: ${(e as Error).message}`);
    }
    if (!res.ok) throw new MoodUnavailable(`mood model answered ${res.status}`);
    const body = (await res.json().catch(() => ({}))) as { choices?: { message?: { content?: unknown } }[] };
    return String(body.choices?.[0]?.message?.content ?? "");
  }
}

/** The model from the environment, or none (the app then predicts on its own). */
export function moodModelFromEnv(env: NodeJS.ProcessEnv = process.env): MoodModel | undefined {
  const apiKey = env.MOOD_API_KEY ?? env.TTS_API_KEY;
  if (!apiKey) return undefined;
  return new OpenAICompatibleChat({
    baseUrl: env.MOOD_BASE_URL ?? "https://api.deepinfra.com/v1/openai",
    model: env.MOOD_MODEL ?? "google/gemma-3-12b-it",
    apiKey,
  });
}

export class MoodService {
  constructor(
    private readonly db: Db,
    private readonly model: MoodModel,
    private readonly clock: () => Date = () => new Date(),
  ) {}

  async suggest(userId: string, req: MoodSuggestRequest): Promise<{ mood: Mood; reason: string }> {
    const day = this.clock().toISOString().slice(0, 10);
    const used = await this.db.query<{ calls: number }>(`select calls from mood_usage where user_id = $1 and day = $2`, [userId, day]);
    if ((used[0]?.calls ?? 0) >= DAILY_MOOD_CALLS) throw new MoodQuotaExceeded(DAILY_MOOD_CALLS);
    await this.db.query(
      `insert into mood_usage (user_id, day, calls) values ($1, $2, 1)
       on conflict (user_id, day) do update set calls = mood_usage.calls + 1`,
      [userId, day],
    );
    const reply = await this.model.complete(MOOD_SYSTEM, buildMoodPrompt(req.log, req.now));
    const out = parseMoodReply(reply);
    if (!out) throw new MoodInvalid("the mood model did not answer with one of the moods");
    return out;
  }
}
