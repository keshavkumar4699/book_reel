import type { ChapterInput, ModelOutput, Sentence } from "../src/segmentation/schema.js";

/** A chapter of `blocks` paragraphs with `perBlock` ~12-word sentences each. */
export function makeChapter(index = 0, blocks = 12, perBlock = 4): ChapterInput {
  const sentences: Sentence[] = [];
  for (let b = 0; b < blocks; b++) {
    for (let s = 0; s < perBlock; s++) {
      sentences.push({
        sid: `c${index}.b${b}.s${s}`,
        text: `Sentence ${s} of paragraph ${b} explains one small idea about habits and their quiet power.`,
        block: "paragraph",
      });
    }
  }
  return { index, title: `Chapter ${index + 1}`, context_before: "", sentences };
}

/** A perfect model answer: one card per two paragraphs (~8 sentences, ~120 words). */
export function perfectOutput(ch: ChapterInput, perCard = 8): ModelOutput {
  const cards = [];
  for (let i = 0; i < ch.sentences.length; i += perCard) {
    const slice = ch.sentences.slice(i, i + perCard);
    cards.push({
      start_sid: slice[0]!.sid,
      end_sid: slice[slice.length - 1]!.sid,
      title: "Why small habits compound",
      hook: "Tiny actions add up faster than you think.",
      type: "argument",
      standalone: true,
      key_sids: [slice[1]!.sid],
      hard_words: [{ word: "habits", sid: slice[0]!.sid, meaning: "repeated behaviours" }],
    });
  }
  return {
    cards,
    recaps: [{ after_card: cards.length - 1, bullets: ["Small habits compound.", "Systems beat goals."] }],
    recalls: [],
    chapter_teaser: "What if the smallest change mattered most?",
  };
}
