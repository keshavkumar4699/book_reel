import type { ChapterInput, PresentationOutput, Sentence, StructureOutput } from "../src/segmentation/schema.js";

/** A chapter of `blocks` paragraphs with `perBlock` ~15-word sentences each. */
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

/** A clean pass-1 answer: one card every `perCard` sentences (8 ≈ 120 words). */
export function structureOutput(ch: ChapterInput, perCard = 8): StructureOutput {
  const cards = [];
  for (let i = 0; i < ch.sentences.length; i += perCard) cards.push({ start_sid: ch.sentences[i]!.sid });
  return {
    cards,
    recaps: [{ after_card: cards.length - 1, bullets: ["Small habits compound.", "Systems beat goals."] }],
    recalls: [],
    chapter_teaser: "What if the smallest change mattered most?",
    scene: "forest",
    scene_cues: [],
  };
}

/** A clean pass-2 answer for the given card numbers. */
export function presentationOutput(cards: { index: number; sentences: Sentence[] }[]): PresentationOutput {
  return {
    cards: cards.map((c) => ({
      card: c.index,
      layout: "centered",
      emphasis: [{ sid: c.sentences[0]!.sid, text: "quiet power", level: 3 }],
      key_sids: [c.sentences[0]!.sid],
      hard_words: [{ word: "habits", sid: c.sentences[0]!.sid, meaning: "repeated behaviours" }],
    })),
  };
}
