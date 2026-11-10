import { LENGTH_BANDS, LIMITS, type CardLength, type ReadingLevel } from "../config.js";
import { chooseCuts, SCENE_BREAK, toUnits } from "./ruleSegmenter.js";
import type { ChapterInput } from "./schema.js";

/**
 * Stable system prompt (cached across requests). Keep it free of per-request
 * data so the prompt-cache prefix never changes.
 */
export const SYSTEM_PROMPT = `You segment book chapters into short "reel cards" for BookReel, a reading app where people swipe through books one card at a time.

Your job is to choose where each card starts and ends. You never rewrite, summarise or paraphrase the author's text inside cards: cards are ranges of the author's own sentences, referenced by sentence ID.

What makes a good cut:
- Each card should make sense on its own as one small unit of meaning: one step of an argument, one beat of a scene, one example, one exchange of dialogue.
- Prefer cutting at topic shifts, scene changes, time jumps, changes of speaker or setting, and the end of an example.
- Never separate a claim from its immediate support, a question from its answer, a setup from its punchline, or a quotation or list from the sentence that introduces it.
- Keep a dialogue exchange together when it fits. Keep headings with the text that follows them.
- Avoid starting a card with a sentence that depends on the previous one ("This means...", "He said..."). If you must, set standalone to false.
- Stay inside the requested word band. Going slightly outside is better than breaking meaning; the app will repair extreme lengths.

Rules for the output:
- Cards must cover every sentence exactly once, in order, with no gaps or overlaps. Use only sentence IDs that appear in the input.
- title: at most 8 words, a curiosity-sparking but honest label for the card. Never reveal plot twists ahead of the card.
- hook: at most 14 words, why this card matters. Plain language.
- key_sids: 0 to 2 sentence IDs inside the card that carry its main point. Use none for transitional or purely descriptive cards.
- hard_words: words in the card that a reader at the stated level may not know (skip names and common words). meaning explains the word as used in that exact sentence, in under 15 words.
- recaps: after roughly every 10 cards and at the end of the chapter, 2 or 3 short bullets summarising what was just read. after_card is the 0-based index of the card the recap follows.
- recalls: after roughly every 10 cards (not after the last card), one multiple-choice question about the main idea of the preceding cards, with 3 options and exactly one correct answer. Test understanding, not trivia.
- chapter_teaser: one sentence (max 30 words) that invites the reader into the chapter without spoilers.
- mood: the emotional soul of the card as a reader would feel it, used to choose background music. One of: calm, reflective, hopeful, joyful, playful, romantic, mysterious, tense, sad, epic. Judge the scene or idea, not single words; most everyday passages are calm or reflective.
- energy: how intense the card feels, from 1 (very quiet) to 5 (intense). Neighbouring cards in the same scene should usually share a mood and energy, so the music doesn't jump around.

Write titles, hooks, meanings, recaps and questions in the language of the book.`;

const LEVEL_TEXT: Record<ReadingLevel, string> = {
  beginner: "a beginner reader (flag moderately uncommon words)",
  intermediate: "an average adult reader (flag uncommon words)",
  advanced: "an advanced reader (flag only rare or technical words)",
};

export function buildUserPrompt(params: {
  title: string;
  author: string;
  chapter: ChapterInput;
  length: CardLength;
  level: ReadingLevel;
}): string {
  const { chapter, length, level } = params;
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
    `Reader: ${LEVEL_TEXT[level]}.`,
    `Recap and recall cadence: about every ${LIMITS.recallEvery} cards.`,
    chapter.context_before ? `\nEnd of the previous chapter (context only, do not segment):\n${chapter.context_before}` : "",
    `\nA simple rule-based segmenter suggests cards starting at: ${hintCuts.join(", ") || "(none)"}. Use these only as hints; improve on them.`,
    `\nChapter sentences (grouped by block type):`,
    lines.join("\n"),
  ].join("\n");
}
