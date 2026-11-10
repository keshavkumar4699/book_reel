import { createHash } from "node:crypto";

import Anthropic from "@anthropic-ai/sdk";
import { z } from "zod";

import { MOODS, MUSIC_PICK_ROUTE } from "../config.js";
import { ModelFailure, parseJson } from "../segmentation/claudeSegmenter.js";
import type { Track } from "./catalog.js";

export const MusicPlanRequestSchema = z.object({
  tier: z.string(),
  book_title: z.string().max(300).optional(),
  teaser: z.string().max(400).optional(),
  cues: z
    .array(
      z.object({
        at_card: z.number().int().min(0),
        mood: z.enum(MOODS),
        energy: z.number().int().min(1).max(5),
        description: z.string().max(120).default(""),
      }),
    )
    .min(1)
    .max(4),
});
export type MusicPlanRequest = z.infer<typeof MusicPlanRequestSchema>;
export type Cue = MusicPlanRequest["cues"][number];

export interface Pick {
  at_card: number;
  track_id: string;
}

const RELATED: Record<string, string[]> = {
  calm: ["reflective", "hopeful"],
  reflective: ["calm", "sad"],
  hopeful: ["joyful", "calm"],
  joyful: ["playful", "hopeful"],
  playful: ["joyful"],
  romantic: ["hopeful", "calm"],
  mysterious: ["tense", "reflective"],
  tense: ["mysterious", "epic"],
  sad: ["reflective", "calm"],
  epic: ["tense", "hopeful"],
};

export function scoreTrack(t: Track, mood: string, energy: number): number {
  const m = t.moods as string[];
  const moodScore = m.includes(mood) ? 3 : (RELATED[mood] ?? []).some((x) => m.includes(x)) ? 1.5 : 0;
  return moodScore - 0.6 * Math.abs(t.energy - energy);
}

/** Deterministic fallback: best mood/energy match, avoiding back-to-back repeats. */
export function rulePicks(cues: Cue[], tracks: Track[]): Pick[] {
  if (tracks.length === 0) return [];
  const picks: Pick[] = [];
  for (const c of cues) {
    const previous = picks.at(-1)?.track_id;
    const ranked = [...tracks].sort((a, b) => scoreTrack(b, c.mood, c.energy) - (b.id === previous ? 2 : 0) - (scoreTrack(a, c.mood, c.energy) - (a.id === previous ? 2 : 0)));
    picks.push({ at_card: c.at_card, track_id: ranked[0]!.id });
  }
  return picks;
}

/** Chooses tracks for cues; behind an interface so tests need no network. */
export interface TrackChooser {
  choose(cues: Cue[], tracks: Track[], context: { book?: string; teaser?: string }): Promise<{ cue: number; track_id: string }[]>;
}

/** Claude as music supervisor: reads the cues and the catalog, picks the best fit. */
export class ClaudeTrackChooser implements TrackChooser {
  constructor(private readonly client: Anthropic = new Anthropic()) {}

  async choose(cues: Cue[], tracks: Track[], context: { book?: string; teaser?: string }) {
    const ids = tracks.map((t) => t.id);
    const schema = {
      type: "object",
      additionalProperties: false,
      required: ["picks"],
      properties: {
        picks: {
          type: "array",
          items: {
            type: "object",
            additionalProperties: false,
            required: ["cue", "track_id"],
            properties: { cue: { type: "integer" }, track_id: { type: "string", enum: ids } },
          },
        },
      },
    };
    const catalog = tracks
      .map((t) => `- ${t.id} | "${t.title}" by ${t.artist} | moods: ${t.moods.join(", ")} | energy ${t.energy}${t.bpm ? ` | ${t.bpm} bpm` : ""}${t.description ? ` | ${t.description}` : ""}`)
      .join("\n");
    const cueText = cues
      .map((c, i) => `${i}. from card ${c.at_card}: ${c.mood}, energy ${c.energy}${c.description ? `, ideal: ${c.description}` : ""}`)
      .join("\n");
    const message = await this.client.messages
      .stream({
        model: MUSIC_PICK_ROUTE.model,
        max_tokens: 4000,
        system: [
          {
            type: "text",
            text:
              "You are the music supervisor for BookReel, a reading app that plays quiet background music while people read. " +
              "For each music cue in a chapter, pick the catalog track that best fits its mood, energy and described feel. " +
              "Reading music should support, not distract: when in doubt prefer the gentler track. " +
              "Avoid using the same track for two consecutive cues unless nothing else fits.",
            cache_control: { type: "ephemeral" },
          },
        ],
        messages: [
          {
            role: "user",
            content: `${context.book ? `Book: ${context.book}\n` : ""}${context.teaser ? `Chapter: ${context.teaser}\n` : ""}\nCatalog:\n${catalog}\n\nCues:\n${cueText}\n\nReturn one pick per cue number.`,
          },
        ],
        output_config: {
          effort: MUSIC_PICK_ROUTE.effort,
          format: { type: "json_schema", schema: schema as unknown as Record<string, unknown> },
        },
      })
      .finalMessage();
    if (message.stop_reason !== "end_turn") throw new ModelFailure(`music pick stopped: ${message.stop_reason}`);
    const text = message.content.map((b) => (b.type === "text" ? b.text : "")).join("");
    return parseJson(text, z.object({ picks: z.array(z.object({ cue: z.number().int(), track_id: z.string() })) })).picks;
  }
}

export class MusicPicker {
  private readonly cache = new Map<string, { picks: Pick[]; source: "ai" | "rules" }>();
  private readonly version: string;

  constructor(
    private readonly tracks: Track[],
    private readonly chooser?: TrackChooser,
  ) {
    this.version = createHash("sha256")
      .update(JSON.stringify(tracks.map((t) => [t.id, t.moods, t.energy, t.description ?? ""])))
      .digest("hex")
      .slice(0, 16);
  }

  async plan(req: MusicPlanRequest): Promise<{ picks: Pick[]; source: "ai" | "rules" | "none" }> {
    if (this.tracks.length === 0) return { picks: [], source: "none" };
    const cues = [...req.cues].sort((a, b) => a.at_card - b.at_card);
    const key = createHash("sha256").update(this.version).update(JSON.stringify(cues)).update(req.teaser ?? "").digest("hex");
    const hit = this.cache.get(key);
    if (hit) return hit;
    let result: { picks: Pick[]; source: "ai" | "rules" } = { picks: rulePicks(cues, this.tracks), source: "rules" };
    if (this.chooser && this.tracks.length > 1) {
      try {
        const ids = new Set(this.tracks.map((t) => t.id));
        const chosen = await this.chooser.choose(cues, this.tracks, { book: req.book_title, teaser: req.teaser });
        const picks = cues.map((c, i) => {
          const p = chosen.find((x) => x.cue === i && ids.has(x.track_id));
          return { at_card: c.at_card, track_id: p?.track_id ?? result.picks[i]!.track_id };
        });
        result = { picks, source: "ai" };
      } catch {
        // keep the rule-based picks
      }
    }
    if (this.cache.size > 5000) this.cache.clear();
    this.cache.set(key, result);
    return result;
  }
}
