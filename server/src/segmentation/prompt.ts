import { LENGTH_BANDS, LIMITS, type CardLength, type ReadingLevel } from "../config.js";
import { chooseCuts, SCENE_BREAK, toUnits } from "./ruleSegmenter.js";
import type { ChapterInput, Sentence } from "./schema.js";

/**
 * Pass 1 system prompt (stable, cached). Keep per-request data out of it so
 * the prompt-cache prefix never changes.
 */
export const STRUCTURE_SYSTEM_PROMPT = `You are the editor and director for BookReel, a reading app where people swipe through books one short card at a time. Each card fills the phone screen over a calm animated scene with its own ambient sound (rain on a window, a café, waves, wind in the pines).

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

## 3. Scene (background picture and sound)
Pick the scene that best fits the chapter's setting and emotional world. The reader sees it and hears its sound:
- forest: pines at dusk with fireflies; wind, birds and crickets (nature, journeys, quiet growth)
- cafe: a warm café on a rainy evening; café murmur and rain (conversation, everyday life, ideas, cozy study)
- rain: city lights through rain at night; steady rain (melancholy, introspection, noir)
- ocean: slow waves after sunset; waves and sea wind (longing, freedom, reflection, endings)
- night: stars over mountains; crickets and night wind (wonder, mystery, dreams, the unknown)
- meadow: a sunny meadow under clouds; birdsong and a breeze (joy, childhood, hope, lightness)
- snow: a quiet snowy cabin at dusk; a crackling fire and wind (solitude, loss, stillness, winter)
- city: a city skyline at night; distant traffic (modern life, ambition, tension, crowds)
scene_cues: up to 3 changes inside the chapter, only when the setting or emotional world clearly changes for a stretch of cards. at_card is the first card in the new scene. Most chapters need none.

Write recaps, questions and the teaser in the language of the book.`;

/** Pass 2 system prompt (stable, cached). */
export const PRESENTATION_SYSTEM_PROMPT = `You are the art director for BookReel. Each card is shown full-screen like a reel: the author's words in one calm, comfortable size, a phrase per line, with emphasised phrases in a brighter colour. A card's single most striking sentence can instead get a spotlight: a screen of its own, in large display type, between the text before and after it. You never rewrite or paraphrase; you only mark phrases that already appear in the card.

For every card you are given, return one entry with the same card number:
- emphasis: 0 to 3 phrases, each copied exactly from one sentence of that card, with that sentence's ID.
  - level 3 (spotlight): the line a reader would quote, at most one per card and only on about one card in four, when something genuinely stands out. Put it in a complete sentence of 3 to 18 words that makes sense on its own screen, and copy either that whole sentence or its strongest phrase (the app shows the whole sentence large and colours the phrase). Text left before or after it in the card should be at least a short sentence; if it would leave a scrap of a few words, use level 2 instead.
  - level 2: key phrases to stress inline, at most 10 words each.
  - Choose meaning over filler: a claim, a vivid image, a turning point, a memorable line of dialogue. Plain transitional cards get no emphasis.
- layout: "centered" for one or two short lines; "left" for longer or descriptive cards (the easiest to read); "staggered" for dialogue, lists or rhythmic, poetic passages.
- key_sids: 0 to 2 sentence IDs that carry the card's main point.
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
