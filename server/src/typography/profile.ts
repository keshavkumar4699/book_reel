import Anthropic from "@anthropic-ai/sdk";
import { z } from "zod";

import { PROFILE_ROUTE, VOICES, type Voice } from "../config.js";
import { ModelFailure, ModelRefusal, parseJson } from "../segmentation/claudeSegmenter.js";

/**
 * Book typography (UX_DESIGN.md Revision 4): which pair of fonts — a body
 * face and a display face — fits a book, chosen from its metadata and a short
 * opening sample. Paid tiers only; the app falls back to its own rules.
 */
export const BookProfileRequestSchema = z.object({
  tier: z.string(),
  book: z.object({
    title: z.string().max(300),
    author: z.string().max(200).default(""),
    content_hash: z.string().min(8).max(128),
  }),
  subjects: z.array(z.string().max(200)).max(12).default([]),
  sample: z.string().max(6000).default(""),
});
export type BookProfileRequest = z.infer<typeof BookProfileRequestSchema>;

export interface BookProfile {
  voice: Voice;
  genre: string;
  source: "ai" | "rules";
}

const VOICE_GUIDE: Record<Voice, string> = {
  classic: "literary and general fiction, classics, essays, history, philosophy, poetry (Literata + DM Serif Display)",
  romance: "romance, love stories, romantic comedy of manners, lyrical memoir (Lora + Playfair Display italic)",
  fantasy: "fantasy, myth, legend, fairy tales for adults, epic adventure (Alegreya + Cinzel)",
  scifi: "science fiction, space, cyberpunk, near-future technology (Exo 2 + Orbitron)",
  suspense: "mystery, detective, thriller, crime, horror, gothic, espionage (Libre Baskerville + Oswald)",
  modern: "non-fiction: self-help, business, productivity, psychology, popular science, technology (Atkinson Hyperlegible + Outfit)",
  playful: "children's books, young readers, humour, whimsical nonsense (Nunito + Fredoka)",
};

const SUBJECT_RULES: [Voice, RegExp][] = [
  ["playful", /juvenile|children|picture book|nursery|humou?r|nonsense/i],
  ["fantasy", /fantasy|fairy tale|mytholog|legend|folklore|magic|dragon|wizard|arthurian/i],
  ["scifi", /science fiction|sci-fi|space opera|cyberpunk|dystopia|robot|time travel|interplanetary/i],
  ["suspense", /myster|detective|thriller|suspense|crime|horror|ghost|murder|gothic|noir|espionage|spy/i],
  ["romance", /romance|love stor|courtship/i],
  ["modern", /self-help|business|management|psycholog|economics|personal development|success|productivity|leadership|finance|popular science/i],
];

/** Deterministic fallback from subject tags (the app has a fuller on-device version). */
export function ruleVoice(req: BookProfileRequest): Voice {
  for (const [voice, re] of SUBJECT_RULES) {
    if (req.subjects.some((s) => re.test(s))) return voice;
  }
  return "classic";
}

/** Chooses a voice; behind an interface so tests need no network. */
export interface VoiceChooser {
  choose(req: BookProfileRequest): Promise<{ voice: Voice; genre: string }>;
}

const PROFILE_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["genre", "voice"],
  properties: {
    genre: { type: "string", description: "Short genre label, e.g. 'cosy mystery' or 'popular psychology'." },
    voice: { type: "string", enum: [...VOICES] },
  },
};

const SYSTEM =
  "You are the book designer for BookReel, a reading app that shows books as short full-screen cards. " +
  "For each book, choose the typographic voice that best matches what the book is, so its fonts feel right " +
  "to someone who knows the book. Judge from the title, author, subject tags and the opening pages. " +
  "When a book mixes genres, choose the one a reader would name first (a children's fantasy is 'playful'; " +
  "a Victorian romance is 'romance'; a literary novel with a murder is still 'classic' unless it reads as a mystery). " +
  "Voices:\n" +
  VOICES.map((v) => `- ${v}: ${VOICE_GUIDE[v]}`).join("\n");

export class ClaudeVoiceChooser implements VoiceChooser {
  constructor(private readonly client: Anthropic = new Anthropic()) {}

  async choose(req: BookProfileRequest) {
    const message = await this.client.messages
      .stream({
        model: PROFILE_ROUTE.model,
        max_tokens: 4000,
        system: [{ type: "text", text: SYSTEM, cache_control: { type: "ephemeral" } }],
        messages: [
          {
            role: "user",
            content:
              `Title: ${req.book.title}\nAuthor: ${req.book.author || "unknown"}\n` +
              `Subjects: ${req.subjects.length ? req.subjects.join("; ") : "none given"}\n\n` +
              `Opening pages:\n<sample>\n${req.sample}\n</sample>\n\nChoose the voice.`,
          },
        ],
        output_config: {
          effort: PROFILE_ROUTE.effort,
          format: { type: "json_schema", schema: PROFILE_SCHEMA as unknown as Record<string, unknown> },
        },
      })
      .finalMessage();
    if (message.stop_reason === "refusal") throw new ModelRefusal("model declined this book");
    if (message.stop_reason !== "end_turn") throw new ModelFailure(`profile stopped: ${message.stop_reason}`);
    const text = message.content.map((b) => (b.type === "text" ? b.text : "")).join("");
    const out = parseJson(text, z.object({ genre: z.string().max(80), voice: z.enum(VOICES) }));
    return { voice: out.voice, genre: out.genre.slice(0, 60) };
  }
}

/** One profile per book, cached by content hash; rules when the AI is unavailable. */
export class BookProfiler {
  private readonly cache = new Map<string, BookProfile>();

  constructor(private readonly chooser?: VoiceChooser) {}

  async profile(req: BookProfileRequest): Promise<BookProfile> {
    const hit = this.cache.get(req.book.content_hash);
    if (hit) return hit;
    let result: BookProfile = { voice: ruleVoice(req), genre: "", source: "rules" };
    if (this.chooser) {
      try {
        const ai = await this.chooser.choose(req);
        result = { ...ai, source: "ai" };
      } catch {
        // Refusal, failure or bad JSON: keep the rule choice, don't cache it.
        return result;
      }
    }
    if (this.cache.size > 5000) this.cache.delete(this.cache.keys().next().value!);
    this.cache.set(req.book.content_hash, result);
    return result;
  }
}
