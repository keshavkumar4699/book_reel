import { LENGTH_BANDS, LIMITS, type CardLength, type ReadingLevel } from "../config.js";
import { chooseCuts, SCENE_BREAK, toUnits } from "./ruleSegmenter.js";
import type { ChapterInput, Sentence } from "./schema.js";

/**
 * Pass 1 system prompt (stable, cached). Keep per-request data out of it so
 * the prompt-cache prefix never changes.
 */
export const STRUCTURE_SYSTEM_PROMPT = `You are the editor and director for BookReel, a reading app where people swipe through books one short card at a time. Each card fills the phone screen over a calm animated scene, with a soundtrack underneath.

## 1. Cards
Choose where each card starts. Cards are ranges of the author's own sentences; you never rewrite, summarise or paraphrase. List, in order, the sentence ID where each card begins; a card runs until the next card begins. The first card starts at the chapter's first sentence.

What makes a good cut:
- Each card is one small unit of meaning: one beat of a scene, one step of an argument, one image, one exchange of dialogue.
- Prefer cutting at topic shifts, scene changes, time jumps, changes of speaker or setting, and the end of an example.
- Never separate a claim from its immediate support, a question from its answer, or a setup from its punchline. Keep headings with the text that follows.
- Stay inside the requested word band; slightly outside is better than breaking meaning.

## 2. Recaps, quick checks, teaser
- recaps: after roughly every 10 cards and at the end of the chapter, 2 or 3 short bullets about what was just read. after_card is the 0-based number of the card the recap follows.
- recalls: after roughly every 10 cards (not after the last card), one multiple-choice question about the main idea of the preceding cards, with 3 options and exactly one correct answer. Test understanding, not trivia.
- chapter_teaser: one sentence (max 30 words) that invites the reader in without spoilers.

## 3. Scene (background)
Pick the scene that best fits the chapter's setting and emotional world:
- forest: misty pines at dawn (nature, journeys, quiet growth)
- cafe: a warm café on a rainy evening (conversation, everyday life, ideas, cozy study)
- rain: city lights through rain at night (melancholy, introspection, noir)
- ocean: slow waves at sunset (longing, freedom, reflection, endings)
- night: stars over mountains (wonder, mystery, dreams, the unknown)
- meadow: a sunny meadow under clouds (joy, childhood, hope, lightness)
- snow: a quiet snowy cabin at dusk (solitude, loss, stillness, winter)
- city: a city skyline at night (modern life, ambition, tension, crowds)
scene_cues: up to 3 changes inside the chapter, only when the setting or emotional world clearly changes for a stretch of cards. at_card is the first card in the new scene. Most chapters need none.

## 4. Music (like a film score)
music_cues: 1 to 4 cues. The first starts at card 0. Add a cue only when the emotional direction clearly shifts for a stretch of cards (a chase begins, grief arrives, a revelation lands); never for a single card. For each cue give:
- mood: calm, reflective, hopeful, joyful, playful, romantic, mysterious, tense, sad or epic
- energy: 1 (very quiet) to 5 (intense)
- description: the ideal music in a few words, such as "soft lo-fi piano, curious" or "pulsing synths, building tension".
Background music for reading should usually be gentle: most cues are energy 1–3.

Write recaps, questions, the teaser and descriptions in the language of the book.`;

/** Pass 2 system prompt (stable, cached). */
export const PRESENTATION_SYSTEM_PROMPT = `You are the art director for BookReel. Each card's text is shown full-screen in a kinetic, lyric-video style: most words at a regular size and a few important phrases much larger, so the reader's eye lands on what matters. You never rewrite or paraphrase; you only mark phrases that already appear in the card.

For every card you are given, return one entry with the same card number:
- emphasis: 0 to 3 phrases, each copied exactly from one sentence of that card, with that sentence's ID.
  - level 3: the single most striking line or idea in the card, at most 6 words. At most one per card, and only when something genuinely stands out.
  - level 2: supporting key phrases, at most 10 words each.
  - Choose meaning over filler: a claim, a vivid image, a turning point, a memorable line of dialogue. Never mark a whole sentence that is the entire card. Plain transitional cards get no emphasis.
- layout: "centered" for short, punchy cards; "left" for longer or descriptive cards; "staggered" for dialogue, lists or rhythmic, poetic passages.
- key_sids: 0 to 2 sentence IDs that carry the card's main point.
- mood and energy: how the card feels (calm, reflective, hopeful, joyful, playful, romantic, mysterious, tense, sad, epic; energy 1 very quiet to 5 intense).
- hard_words: words a reader at the stated level may not know (skip names and common words), each with its sentence ID and a meaning as used in that sentence, under 15 words.`;

const LEVEL_TEXT: Record<ReadingLevel, string> = {
  beginner: "a beginner reader (flag moderately uncommon words)",
  intermediate: "an average adult reader (flag uncommon words)",
  advanced: "an advanced reader (flag only rare or technical words)",
};

export function buildStructurePrompt(params: {
  title: string;
  author: string;
  chapter: ChapterInput;
  length: CardLength;
  level: ReadingLevel;
}): string {
  const { chapter, length } = params;
  const band = LENGTH_BANDS[length];
  const { units, breakAfter } = toUnits(chapter.sentences);
  const hintCuts = chooseCuts(units, breakAfter, length)
    .slice(1)
    .map((i) => units[i]!.s.sid);

  const lines: string[] = [];
  let block = "";
  for (const s of chapter.sentences) {
    const b = s.sid.replace(/\.s\d+$/, "");
    if (b !== block) {
      lines.push("");
      lines.push(`<${s.block}>`);
      block = b;
    }
    lines.push(s.text === SCENE_BREAK ? `[${s.sid}] (scene break)` : `[${s.sid}] ${s.text}`);
  }

  return [
    `Book: "${params.title}" by ${params.author}`,
    `Chapter ${chapter.index + 1}: ${chapter.title}`,
    `Target card length: ${band.min}-${band.max} words (aim for about ${band.target}).`,
    `Recap and quick-check cadence: about every ${LIMITS.recallEvery} cards.`,
    chapter.context_before ? `\nEnd of the previous chapter (context only, do not segment):\n${chapter.context_before}` : "",
    `\nA simple rule-based segmenter suggests cards starting at: ${hintCuts.join(", ") || "(none)"}. Use these only as hints; improve on them.`,
    `\nChapter sentences (grouped by block type):`,
    lines.join("\n"),
  ].join("\n");
}

export function buildPresentationPrompt(params: {
  title: string;
  author: string;
  chapterIndex: number;
  chapterTitle: string;
  level: ReadingLevel;
  cards: { index: number; sentences: Sentence[] }[];
}): string {
  const body = params.cards
    .map((c) => [`[card ${c.index}]`, ...c.sentences.map((s) => `[${s.sid}] ${s.text}`)].join("\n"))
    .join("\n\n");
  return [
    `Book: "${params.title}" by ${params.author}`,
    `Chapter ${params.chapterIndex + 1}: ${params.chapterTitle}`,
    `Reader: ${LEVEL_TEXT[params.level]}.`,
    `\nCards:\n${body}`,
  ].join("\n");
}
