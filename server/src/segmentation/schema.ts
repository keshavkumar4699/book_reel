import { z } from "zod";

import { LAYOUTS, MOODS, SCENES } from "../config.js";

export const BlockTypeSchema = z.enum(["heading", "paragraph", "quote", "list", "dialogue", "preformatted"]);

export const SentenceSchema = z.object({
  sid: z.string().regex(/^c\d+\.b\d+\.s\d+$/),
  text: z.string().max(5000),
  block: BlockTypeSchema,
});

export const ChapterInputSchema = z.object({
  index: z.number().int().min(0),
  title: z.string().max(300),
  context_before: z.string().max(4000).default(""),
  sentences: z.array(SentenceSchema).min(1).max(4000),
});

export const SegmentRequestSchema = z.object({
  book: z.object({
    content_hash: z.string().regex(/^[a-f0-9]{64}$/),
    title: z.string().max(500),
    author: z.string().max(300),
    language: z.string().max(20).default("en"),
  }),
  tier: z.enum(["free", "plus", "pro", "scholar"]),
  card_length: z.enum(["snack", "bite", "standard", "deep"]).default("snack"),
  reading_level: z.enum(["beginner", "intermediate", "advanced"]).default("intermediate"),
  priority: z.enum(["now", "background"]).default("now"),
  chapters: z.array(ChapterInputSchema).min(1).max(3),
});

export type Sentence = z.infer<typeof SentenceSchema>;
export type ChapterInput = z.infer<typeof ChapterInputSchema>;
export type SegmentRequest = z.infer<typeof SegmentRequestSchema>;

// ---------------------------------------------------------------------------
// Pass 1 — structure & direction (tier model): where cards start, recaps,
// recall questions, teaser, the chapter's scenes and its music cues.

export const StructureOutputSchema = z.object({
  cards: z.array(z.object({ start_sid: z.string() })),
  recaps: z.array(z.object({ after_card: z.number().int(), bullets: z.array(z.string()) })),
  recalls: z.array(
    z.object({ after_card: z.number().int(), question: z.string(), options: z.array(z.string()), answer_index: z.number().int() }),
  ),
  chapter_teaser: z.string(),
  scene: z.string(),
  scene_cues: z.array(z.object({ at_card: z.number().int(), scene: z.string() })),
  music_cues: z.array(z.object({ at_card: z.number().int(), mood: z.string(), energy: z.number().int(), description: z.string() })),
});
export type StructureOutput = z.infer<typeof StructureOutputSchema>;

const obj = (properties: Record<string, unknown>) => ({
  type: "object",
  additionalProperties: false,
  required: Object.keys(properties),
  properties,
});
const arr = (items: unknown) => ({ type: "array", items });
const str = { type: "string" };
const int = { type: "integer" };

/** JSON schema for Claude structured outputs (closed objects, all fields required). */
export const STRUCTURE_JSON_SCHEMA = obj({
  cards: arr(obj({ start_sid: str })),
  recaps: arr(obj({ after_card: int, bullets: arr(str) })),
  recalls: arr(obj({ after_card: int, question: str, options: arr(str), answer_index: int })),
  chapter_teaser: str,
  scene: { type: "string", enum: [...SCENES] },
  scene_cues: arr(obj({ at_card: int, scene: { type: "string", enum: [...SCENES] } })),
  music_cues: arr(
    obj({ at_card: int, mood: { type: "string", enum: [...MOODS] }, energy: { type: "integer", enum: [1, 2, 3, 4, 5] }, description: str }),
  ),
});

// ---------------------------------------------------------------------------
// Pass 2 — art direction per card (fast model): which phrases to make big,
// layout, key sentences, mood/energy, hard words.

export const PresentationOutputSchema = z.object({
  cards: z.array(
    z.object({
      card: z.number().int(),
      layout: z.string(),
      emphasis: z.array(z.object({ sid: z.string(), text: z.string(), level: z.number().int() })),
      key_sids: z.array(z.string()),
      mood: z.string(),
      energy: z.number().int(),
      hard_words: z.array(z.object({ word: z.string(), sid: z.string(), meaning: z.string() })),
    }),
  ),
});
export type PresentationOutput = z.infer<typeof PresentationOutputSchema>;

export const PRESENTATION_JSON_SCHEMA = obj({
  cards: arr(
    obj({
      card: int,
      layout: { type: "string", enum: [...LAYOUTS] },
      emphasis: arr(obj({ sid: str, text: str, level: { type: "integer", enum: [2, 3] } })),
      key_sids: arr(str),
      mood: { type: "string", enum: [...MOODS] },
      energy: { type: "integer", enum: [1, 2, 3, 4, 5] },
      hard_words: arr(obj({ word: str, sid: str, meaning: str })),
    }),
  ),
});

// ---------------------------------------------------------------------------
// What the app receives (app/lib/data/ai_client.dart → parseServerChapter).

export interface Emphasis {
  sid: string;
  /** Exact substring of the sentence. */
  text: string;
  /** 2 = large, 3 = hero. */
  level: number;
}

export interface OutCard {
  start_sid: string;
  end_sid: string;
  type: string;
  standalone: boolean;
  key_sids: string[];
  hard_words: { word: string; sid: string; meaning?: string }[];
  /** Emotional tone of the card; absent for rule-based cards. */
  mood?: string;
  /** 1 (very quiet) – 5 (intense). */
  energy?: number;
  emphasis?: Emphasis[];
  layout?: string;
  title?: string;
  hook?: string;
}

export interface SceneCue {
  at_card: number;
  scene: string;
}

export interface MusicCue {
  at_card: number;
  mood: string;
  energy: number;
  /** Ideal music in a few words, e.g. "soft lo-fi piano, curious". */
  description: string;
}

export interface OutChapter {
  index: number;
  source: "ai" | "rules";
  cards: OutCard[];
  recaps: { after_card: number; bullets: string[] }[];
  recalls: { after_card: number; question: string; options: string[]; answer_index: number }[];
  teaser?: string;
  /** Default background scene for the chapter. */
  scene?: string;
  scene_cues: SceneCue[];
  music_cues: MusicCue[];
  /** Set when the validator had to repair the structure. */
  repaired?: number;
  /** Number of cards that received art direction. */
  presented?: number;
}
