import { LENGTH_BANDS, type CardLength } from "../config.js";
import type { OutCard, OutChapter, Sentence } from "./schema.js";

/**
 * Stage 1 rule segmenter (DESIGN.md §4.2). TypeScript port of
 * app/lib/core/segmentation/rule_segmenter.dart, used as the fallback when
 * the model refuses or its output can't be repaired, and to split
 * over-long AI cards at the best boundary.
 */
export const SCENE_BREAK = "⁂";

const DISCOURSE = [
  "however", "meanwhile", "in contrast", "on the other hand", "nevertheless", "later", "the next",
  "first", "second", "third", "finally", "in conclusion", "to begin", "consider", "another", "now,",
];
const BACK_REFS = new Set([
  "this", "that", "these", "those", "it", "he", "she", "they", "his", "her", "their", "its", "such",
  "but", "and", "so", "thus", "hence", "therefore", "yet", "or", "nor", "also", "then",
]);

const WORD_RE = /[\p{L}\p{N}][\p{L}\p{N}'’-]*/gu;
export const countWords = (text: string): number => text.match(WORD_RE)?.length ?? 0;

export const blockOf = (sid: string): number => Number(/\.b(\d+)\./.exec(sid)?.[1] ?? -1);

export function startsWithBackReference(text: string): boolean {
  const m = /^[\s“"'‘(]*([A-Za-z]+)/.exec(text);
  return m !== null && BACK_REFS.has(m[1]!.toLowerCase());
}

interface Unit {
  s: Sentence;
  words: number;
  block: number;
}

/** Score of cutting between `before` and `after`. */
export function boundaryScore(before: Unit, after: Unit, sceneBreak: boolean): number {
  if (sceneBreak) return 1.2;
  if (before.s.block === "heading" && before.block !== after.block) return -1.5;
  let score: number;
  if (before.block === after.block) {
    score = before.s.block === "paragraph" ? 0.05 : before.s.block === "heading" ? -1.5 : -1.0;
  } else {
    score = 0.5;
    if (after.s.block === "heading") score += 0.6;
    if (before.s.block === "dialogue" && after.s.block === "dialogue") score -= 0.6;
    if (before.s.block === "list" && after.s.block === "list") score -= 0.5;
    const lower = after.s.text.toLowerCase();
    if (DISCOURSE.some((d) => lower.startsWith(d))) score += 0.2;
  }
  if (startsWithBackReference(after.s.text)) score -= 0.5;
  return score;
}

/** Content sentences (scene-break markers removed) with the indexes after which a break occurred. */
export function toUnits(sentences: Sentence[]): { units: Unit[]; breakAfter: Set<number> } {
  const units: Unit[] = [];
  const breakAfter = new Set<number>();
  for (const s of sentences) {
    if (s.text === SCENE_BREAK) {
      if (units.length > 0) breakAfter.add(units.length - 1);
      continue;
    }
    units.push({ s, words: countWords(s.text), block: blockOf(s.sid) });
  }
  return { units, breakAfter };
}

/** Returns cut positions (indexes into units where a new card starts), always including 0. */
export function chooseCuts(units: Unit[], breakAfter: Set<number>, length: CardLength): number[] {
  const band = LENGTH_BANDS[length];
  const n = units.length;
  if (n === 0) return [];
  const boundary = new Array<number>(n + 1).fill(0);
  boundary[n] = 1;
  for (let k = 1; k < n; k++) boundary[k] = boundaryScore(units[k - 1]!, units[k]!, breakAfter.has(k - 1));
  const prefix = new Array<number>(n + 1).fill(0);
  for (let i = 0; i < n; i++) prefix[i + 1] = prefix[i]! + units[i]!.words;

  const penalty = (words: number, single: boolean, tail: boolean): number => {
    let p = 0.6 * ((words - band.target) / band.target) ** 2;
    if (words < band.min) p += (tail ? 0.4 : 2.0) + (3.0 * (band.min - words)) / band.min;
    if (words > band.max && !single) p += 2.0 + (3.0 * (words - band.max)) / band.max;
    return p;
  };

  const best = new Array<number>(n + 1).fill(Number.NEGATIVE_INFINITY);
  const prev = new Array<number>(n + 1).fill(-1);
  best[0] = 0;
  for (let k = 1; k <= n; k++) {
    for (let j = k - 1; j >= 0; j--) {
      const words = prefix[k]! - prefix[j]!;
      const single = j === k - 1;
      if (!single && words > band.max * 2) break;
      if (best[j] === Number.NEGATIVE_INFINITY) continue;
      const score = best[j]! + boundary[k]! - penalty(words, single, k === n);
      if (score > best[k]!) {
        best[k] = score;
        prev[k] = j;
      }
    }
  }
  const cuts: number[] = [];
  for (let k = n; k > 0; k = prev[k]!) cuts.push(prev[k]!);
  return cuts.reverse();
}

export function ruleSegmentChapter(index: number, sentences: Sentence[], length: CardLength): OutChapter {
  const { units, breakAfter } = toUnits(sentences);
  const cuts = chooseCuts(units, breakAfter, length);
  const cards: OutCard[] = [];
  for (let c = 0; c < cuts.length; c++) {
    const start = cuts[c]!;
    const end = (cuts[c + 1] ?? units.length) - 1;
    cards.push({
      start_sid: units[start]!.s.sid,
      end_sid: units[end]!.s.sid,
      type: "narrative",
      standalone: !startsWithBackReference(units[start]!.s.text),
      key_sids: [],
      hard_words: [],
    });
  }
  return { index, source: "rules", cards, recaps: [], recalls: [] };
}
