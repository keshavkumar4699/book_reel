import { z } from "zod";

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
  card_length: z.enum(["bite", "standard", "deep"]).default("standard"),
  reading_level: z.enum(["beginner", "intermediate", "advanced"]).default("intermediate"),
  priority: z.enum(["now", "background"]).default("now"),
  chapters: z.array(ChapterInputSchema).min(1).max(3),
});

export type Sentence = z.infer<typeof SentenceSchema>;
export type ChapterInput = z.infer<typeof ChapterInputSchema>;
export type SegmentRequest = z.infer<typeof SegmentRequestSchema>;

/** What the model returns for one chapter (validated with Zod after parsing). */
export const ModelCardSchema = z.object({
  start_sid: z.string(),
  end_sid: z.string(),
  title: z.string(),
  hook: z.string(),
  type: z.string(),
  standalone: z.boolean(),
  key_sids: z.array(z.string()),
  hard_words: z.array(z.object({ word: z.string(), sid: z.string(), meaning: z.string() })),
});

export const ModelOutputSchema = z.object({
  cards: z.array(ModelCardSchema),
  recaps: z.array(z.object({ after_card: z.number().int(), bullets: z.array(z.string()) })),
  recalls: z.array(
    z.object({
      after_card: z.number().int(),
      question: z.string(),
      options: z.array(z.string()),
      answer_index: z.number().int(),
    }),
  ),
  chapter_teaser: z.string(),
});

export type ModelCard = z.infer<typeof ModelCardSchema>;
export type ModelOutput = z.infer<typeof ModelOutputSchema>;

/**
 * JSON schema for Claude structured outputs (`output_config.format`). Written
 * by hand so every object is closed and every field required.
 */
export const MODEL_OUTPUT_JSON_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["cards", "recaps", "recalls", "chapter_teaser"],
  properties: {
    cards: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["start_sid", "end_sid", "title", "hook", "type", "standalone", "key_sids", "hard_words"],
        properties: {
          start_sid: { type: "string" },
          end_sid: { type: "string" },
          title: { type: "string" },
          hook: { type: "string" },
          type: {
            type: "string",
            enum: ["narrative", "argument", "example", "dialogue", "definition", "description", "summary", "quote"],
          },
          standalone: { type: "boolean" },
          key_sids: { type: "array", items: { type: "string" } },
          hard_words: {
            type: "array",
            items: {
              type: "object",
              additionalProperties: false,
              required: ["word", "sid", "meaning"],
              properties: { word: { type: "string" }, sid: { type: "string" }, meaning: { type: "string" } },
            },
          },
        },
      },
    },
    recaps: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["after_card", "bullets"],
        properties: { after_card: { type: "integer" }, bullets: { type: "array", items: { type: "string" } } },
      },
    },
    recalls: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["after_card", "question", "options", "answer_index"],
        properties: {
          after_card: { type: "integer" },
          question: { type: "string" },
          options: { type: "array", items: { type: "string" } },
          answer_index: { type: "integer" },
        },
      },
    },
    chapter_teaser: { type: "string" },
  },
} as const;

/** Card/chapter shape returned to the app (app/lib/data/ai_client.dart). */
export interface OutCard {
  start_sid: string;
  end_sid: string;
  title?: string;
  hook?: string;
  type: string;
  standalone: boolean;
  key_sids: string[];
  hard_words: { word: string; sid: string; meaning?: string }[];
}

export interface OutChapter {
  index: number;
  source: "ai" | "rules";
  cards: OutCard[];
  recaps: { after_card: number; bullets: string[] }[];
  recalls: { after_card: number; question: string; options: string[]; answer_index: number }[];
  teaser?: string;
  /** Set when the validator had to repair the model output. */
  repaired?: number;
}
