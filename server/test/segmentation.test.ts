import { describe, expect, it } from "vitest";

import { LENGTH_BANDS } from "../src/config.js";
import { buildPresentationPrompt, buildStructurePrompt, PRESENTATION_SYSTEM_PROMPT, STRUCTURE_SYSTEM_PROMPT } from "../src/segmentation/prompt.js";
import { countWords, ruleSegmentChapter, SCENE_BREAK } from "../src/segmentation/ruleSegmenter.js";
import { applyPresentation, cardSentences, InvalidModelOutput, validateStructure } from "../src/segmentation/validator.js";
import { makeChapter, presentationOutput, structureOutput } from "./fixtures.js";

const sidsOf = (ch: ReturnType<typeof makeChapter>, start: string, end: string) => {
  const ids = ch.sentences.map((s) => s.sid);
  return ids.slice(ids.indexOf(start), ids.indexOf(end) + 1);
};

describe("rule segmenter", () => {
  it("covers every sentence in order and stays in band", () => {
    const ch = makeChapter(0, 20, 4);
    const out = ruleSegmentChapter(0, ch.sentences, "standard");
    expect(out.cards.flatMap((c) => sidsOf(ch, c.start_sid, c.end_sid))).toEqual(ch.sentences.map((s) => s.sid));
    const band = LENGTH_BANDS.standard;
    for (const c of out.cards) {
      const words = sidsOf(ch, c.start_sid, c.end_sid).length * 15;
      expect(words).toBeGreaterThanOrEqual(band.min - 15);
      expect(words).toBeLessThanOrEqual(band.max + 15);
    }
  });

  it("treats scene breaks as cuts and excludes them from cards", () => {
    const ch = makeChapter(0, 6, 4);
    ch.sentences.splice(12, 0, { sid: "c0.b99.s0", text: SCENE_BREAK, block: "preformatted" });
    const out = ruleSegmentChapter(0, ch.sentences, "bite");
    expect(out.cards.some((c) => c.end_sid === "c0.b2.s3")).toBe(true);
    expect(out.cards.every((c) => c.start_sid !== "c0.b99.s0" && c.end_sid !== "c0.b99.s0")).toBe(true);
  });

  it("counts words like the app", () => {
    expect(countWords("It’s a well-known fact, isn't it?")).toBe(6);
  });
});

describe("pass 1: structure", () => {
  it("turns card starts into contiguous cards and keeps direction", () => {
    const ch = makeChapter();
    const v = validateStructure(0, ch.sentences, structureOutput(ch), "standard");
    expect(v.repairRate).toBe(0);
    expect(v.chapter.cards).toHaveLength(6);
    expect(v.chapter.cards.flatMap((c) => sidsOf(ch, c.start_sid, c.end_sid))).toEqual(ch.sentences.map((s) => s.sid));
    expect(v.chapter.scene).toBe("forest");
    expect(v.chapter.recaps[0]!.after_card).toBe(5);
  });

  it("adds a missing first card, merges tiny cards, splits huge ones", () => {
    const ch = makeChapter();
    const out = structureOutput(ch);
    out.cards.shift(); // no card at the first sentence
    out.cards.splice(1, 0, { start_sid: "c0.b3.s1" }); // a 1-sentence card
    const v = validateStructure(0, ch.sentences, out, "standard");
    expect(v.chapter.cards[0]!.start_sid).toBe("c0.b0.s0");
    const band = LENGTH_BANDS.standard;
    for (const c of v.chapter.cards) {
      const words = sidsOf(ch, c.start_sid, c.end_sid).reduce((a, sid) => a + countWords(ch.sentences.find((s) => s.sid === sid)!.text), 0);
      expect(words).toBeGreaterThanOrEqual(band.min * 0.5);
      expect(words).toBeLessThanOrEqual(band.max);
    }
    expect(v.repairs).toBeGreaterThan(0);
  });

  it("remaps cues and recaps onto repaired cards and drops invalid ones", () => {
    const ch = makeChapter(0, 12, 4); // 48 sentences
    const out = structureOutput(ch, 4); // 12 model cards of ~60 words (bite band keeps them)
    out.scene_cues = [
      { at_card: 6, scene: "night" },
      { at_card: 8, scene: "night" }, // same as previous: dropped
      { at_card: 9, scene: "volcano" }, // unknown scene: dropped
    ];
    out.scene_cues.push({ at_card: 10, scene: "rain" });
    out.recaps = [{ after_card: 5, bullets: ["a"] }];
    const v = validateStructure(0, ch.sentences, out, "bite");
    expect(v.chapter.cards).toHaveLength(12);
    expect(v.chapter.scene_cues).toEqual([
      { at_card: 6, scene: "night" },
      { at_card: 10, scene: "rain" },
    ]);
    expect(v.chapter.recaps[0]!.after_card).toBe(5);

    // Merge two model cards into one by asking for a bigger band: card numbers shift.
    const merged = validateStructure(0, ch.sentences, out, "standard");
    expect(merged.chapter.cards.length).toBeLessThan(12);
    const cue = merged.chapter.scene_cues[1]!;
    const cueCard = merged.chapter.cards[cue.at_card]!;
    expect(sidsOf(ch, cueCard.start_sid, cueCard.end_sid)).toContain(out.cards[10]!.start_sid);
  });

  it("rejects hallucinated sentence ids", () => {
    const ch = makeChapter();
    const out = structureOutput(ch);
    out.cards[2] = { start_sid: "c0.b77.s0" };
    expect(() => validateStructure(0, ch.sentences, out, "standard")).toThrow(InvalidModelOutput);
  });
});

describe("pass 2: art direction", () => {
  const ch = makeChapter();
  const chapter = validateStructure(0, ch.sentences, structureOutput(ch), "standard").chapter;
  const cards = cardSentences(chapter, ch.sentences).map((sentences, index) => ({ index, sentences }));

  it("merges emphasis, layout and words into the cards", () => {
    const r = applyPresentation(chapter, ch.sentences, presentationOutput(cards));
    expect(r.applied).toBe(6);
    expect(r.chapter.presented).toBe(6);
    expect(r.chapter.cards[0]).toMatchObject({
      layout: "centered",
      key_sids: ["c0.b0.s0"],
      emphasis: [{ sid: "c0.b0.s0", text: "quiet power", level: 3 }],
    });
  });

  it("only accepts phrases that really appear in that card's sentence", () => {
    const out = presentationOutput(cards.slice(0, 1));
    out.cards[0]!.emphasis = [
      { sid: "c0.b0.s0", text: "QUIET POWER", level: 3 }, // case differs: kept with the author's casing
      { sid: "c0.b0.s0", text: "invented phrase", level: 2 }, // not in the text
      { sid: "c0.b5.s0", text: "small idea", level: 2 }, // another card's sentence
      { sid: "c0.b0.s1", text: "small idea about habits", level: 3 }, // second hero → demoted to 2
      { sid: "c0.b0.s0", text: "power", level: 2 }, // overlaps the first phrase
      { sid: "c0.b0.s2", text: ch.sentences[2]!.text, level: 2 }, // the whole sentence
    ];
    const r = applyPresentation(chapter, ch.sentences, out);
    expect(r.chapter.cards[0]!.emphasis).toEqual([
      { sid: "c0.b0.s0", text: "quiet power", level: 3 },
      { sid: "c0.b0.s1", text: "small idea about habits", level: 2 },
    ]);
    expect(r.dropped).toBe(4);
  });

  it("spotlights: a whole short sentence is allowed; long sentences are demoted to inline", () => {
    const long = "This sentence keeps going for quite a while so that it is far too long to be shown as a large spotlight line on its own.";
    const sentences = [
      { sid: "c0.b0.s0", text: "Small habits compound quietly.", block: "paragraph" as const },
      { sid: "c0.b0.s1", text: long, block: "paragraph" as const },
      { sid: "c0.b0.s2", text: "Another ordinary sentence closes the card for now.", block: "paragraph" as const },
    ];
    const single = validateStructure(0, sentences, { ...structureOutput({ index: 0, title: "T", context_before: "", sentences }), cards: [{ start_sid: "c0.b0.s0" }] }, "standard").chapter;
    const base = presentationOutput([{ index: 0, sentences }]);
    base.cards[0]!.emphasis = [
      { sid: "c0.b0.s0", text: "Small habits compound quietly.", level: 3 }, // whole short sentence: spotlight
      { sid: "c0.b0.s1", text: "far too long", level: 3 }, // second hero, long sentence → inline
    ];
    expect(applyPresentation(single, sentences, base).chapter.cards[0]!.emphasis).toEqual([
      { sid: "c0.b0.s0", text: "Small habits compound quietly.", level: 3 },
      { sid: "c0.b0.s1", text: "far too long", level: 2 },
    ]);
    base.cards[0]!.emphasis = [{ sid: "c0.b0.s1", text: "far too long", level: 3 }];
    expect(applyPresentation(single, sentences, base).chapter.cards[0]!.emphasis).toEqual([{ sid: "c0.b0.s1", text: "far too long", level: 2 }]);
  });

  it("ignores unknown card numbers and invalid layouts", () => {
    const out = presentationOutput(cards.slice(0, 1));
    out.cards.push({ ...out.cards[0]!, card: 99 });
    out.cards[0]!.layout = "spiral";
    const r = applyPresentation(chapter, ch.sentences, out);
    expect(r.chapter.cards[0]!.layout).toBeUndefined();
    expect(r.dropped).toBeGreaterThan(0);
  });
});

describe("prompts", () => {
  it("number sentences, group cards and keep per-request data out of system prompts", () => {
    const ch = makeChapter(2, 3, 2);
    const p = buildStructurePrompt({ title: "Atomic", author: "A", chapter: ch, length: "snack", level: "beginner" });
    expect(p).toContain("[c2.b0.s0] Sentence 0 of paragraph 0");
    expect(p).toContain("12-55 words");
    const q = buildPresentationPrompt({ title: "Atomic", author: "A", chapterIndex: 2, chapterTitle: "T", level: "advanced", cards: [{ index: 4, sentences: ch.sentences.slice(0, 2) }] });
    expect(q).toContain("[card 4]");
    expect(q).toContain("advanced reader");
    expect(STRUCTURE_SYSTEM_PROMPT + PRESENTATION_SYSTEM_PROMPT).not.toContain("Atomic");
    for (const scene of ["forest", "cafe", "rain", "ocean", "night", "meadow", "snow", "city"]) expect(STRUCTURE_SYSTEM_PROMPT).toContain(`- ${scene}:`);
  });
});
