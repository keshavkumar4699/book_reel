import { describe, expect, it } from "vitest";

import { LENGTH_BANDS } from "../src/config.js";
import { buildUserPrompt, SYSTEM_PROMPT } from "../src/segmentation/prompt.js";
import { countWords, ruleSegmentChapter, SCENE_BREAK } from "../src/segmentation/ruleSegmenter.js";
import { InvalidModelOutput, validateAndRepair } from "../src/segmentation/validator.js";
import { makeChapter, perfectOutput } from "./fixtures.js";

const sidsOf = (ch: ReturnType<typeof makeChapter>, start: string, end: string) => {
  const ids = ch.sentences.map((s) => s.sid);
  return ids.slice(ids.indexOf(start), ids.indexOf(end) + 1);
};

describe("rule segmenter", () => {
  it("covers every sentence in order and stays in band", () => {
    const ch = makeChapter(0, 20, 4);
    const out = ruleSegmentChapter(0, ch.sentences, "standard");
    const covered = out.cards.flatMap((c) => sidsOf(ch, c.start_sid, c.end_sid));
    expect(covered).toEqual(ch.sentences.map((s) => s.sid));
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

describe("validator", () => {
  it("accepts a good answer unchanged", () => {
    const ch = makeChapter();
    const v = validateAndRepair(0, ch.sentences, perfectOutput(ch), "standard");
    expect(v.repairRate).toBe(0);
    expect(v.chapter.cards).toHaveLength(6);
    expect(v.chapter.cards[0]!.key_sids).toEqual(["c0.b0.s1"]);
    expect(v.chapter.recaps).toHaveLength(1);
  });

  it("repairs gaps, overlaps and a missing tail", () => {
    const ch = makeChapter();
    const out = perfectOutput(ch);
    out.cards[1]!.start_sid = "c0.b2.s2"; // gap of two sentences after card 0
    out.cards[3]!.start_sid = "c0.b5.s0"; // overlaps card 2
    out.cards.pop(); // tail missing
    const v = validateAndRepair(0, ch.sentences, out, "standard");
    const covered = v.chapter.cards.flatMap((c) => sidsOf(ch, c.start_sid, c.end_sid));
    expect(covered).toEqual(ch.sentences.map((s) => s.sid));
    expect(v.repairs).toBeGreaterThan(0);
  });

  it("merges too-short cards and splits too-long cards", () => {
    const ch = makeChapter();
    const out = perfectOutput(ch);
    // card 0 → two tiny cards; last two cards → one huge card
    const first = out.cards[0]!;
    out.cards.splice(0, 1, { ...first, end_sid: "c0.b0.s0" }, { ...first, start_sid: "c0.b0.s1", end_sid: "c0.b1.s3" });
    const merged = { ...out.cards[out.cards.length - 2]!, end_sid: out.cards[out.cards.length - 1]!.end_sid };
    out.cards.splice(out.cards.length - 2, 2, merged);
    const v = validateAndRepair(0, ch.sentences, out, "standard");
    const band = LENGTH_BANDS.standard;
    for (const c of v.chapter.cards) {
      const words = sidsOf(ch, c.start_sid, c.end_sid).reduce((a, sid) => a + countWords(ch.sentences.find((s) => s.sid === sid)!.text), 0);
      expect(words).toBeGreaterThanOrEqual(band.min * 0.5);
      expect(words).toBeLessThanOrEqual(band.max);
    }
  });

  it("rejects hallucinated sentence ids", () => {
    const ch = makeChapter();
    const out = perfectOutput(ch);
    out.cards[2]!.end_sid = "c0.b77.s0";
    expect(() => validateAndRepair(0, ch.sentences, out, "standard")).toThrow(InvalidModelOutput);
  });

  it("drops extras that point outside the card or at words not in the sentence", () => {
    const ch = makeChapter();
    const out = perfectOutput(ch);
    out.cards[0]!.key_sids = ["c0.b0.s1", "c0.b9.s0"];
    out.cards[0]!.hard_words.push({ word: "zeugma", sid: "c0.b0.s0", meaning: "x" });
    out.cards[0]!.title = "one two three four five six seven eight nine ten";
    out.recalls = [{ after_card: 0, question: "q", options: ["a", "b", "c"], answer_index: 7 }];
    const v = validateAndRepair(0, ch.sentences, out, "standard");
    expect(v.chapter.cards[0]!.key_sids).toEqual(["c0.b0.s1"]);
    expect(v.chapter.cards[0]!.hard_words.map((h) => h.word)).toEqual(["habits"]);
    expect(v.chapter.cards[0]!.title).toBe("one two three four five six seven eight…");
    expect(v.chapter.recalls).toHaveLength(0);
  });
});

describe("prompt", () => {
  it("numbers sentences, groups blocks and keeps per-request data out of the system prompt", () => {
    const ch = makeChapter(2, 3, 2);
    const p = buildUserPrompt({ title: "Atomic", author: "A", chapter: ch, length: "bite", level: "beginner" });
    expect(p).toContain("[c2.b0.s0] Sentence 0 of paragraph 0");
    expect(p).toContain("<paragraph>");
    expect(p).toContain("45-110 words");
    expect(SYSTEM_PROMPT).not.toContain("Atomic");
  });
});
