import { LENGTH_BANDS, LIMITS, MOODS, type CardLength } from "../config.js";
import { boundaryScore, countWords, SCENE_BREAK, toUnits } from "./ruleSegmenter.js";
import type { ModelOutput, OutCard, OutChapter, Sentence } from "./schema.js";

export interface ValidationResult {
  chapter: OutChapter;
  /** Number of repairs applied (gaps filled, overlaps trimmed, merges, splits, dropped extras). */
  repairs: number;
  /** Share of cards that needed a structural repair. */
  repairRate: number;
}

export class InvalidModelOutput extends Error {}

/**
 * Stage 3 validator & repairer (DESIGN.md §4.2). Enforces in code what the
 * model is only asked to do: every sentence in exactly one card, in order,
 * cards inside the length band, extras that reference real sentences.
 * Throws [InvalidModelOutput] when the output references unknown sentence
 * IDs (a sign of a hallucinated or corrupted answer).
 */
export function validateAndRepair(
  index: number,
  sentences: Sentence[],
  output: ModelOutput,
  length: CardLength,
): ValidationResult {
  const band = LENGTH_BANDS[length];
  const { units, breakAfter } = toUnits(sentences);
  if (units.length === 0) throw new InvalidModelOutput("chapter has no sentences");
  const pos = new Map(units.map((u, i) => [u.s.sid, i]));
  const sceneSids = new Set(sentences.filter((s) => s.text === SCENE_BREAK).map((s) => s.sid));

  // 1. Map model cards to unit ranges; unknown IDs invalidate the answer.
  const ranges: { start: number; end: number; card: (typeof output.cards)[number] }[] = [];
  for (const card of output.cards) {
    if (sceneSids.has(card.start_sid) || sceneSids.has(card.end_sid)) continue;
    const start = pos.get(card.start_sid);
    const end = pos.get(card.end_sid);
    if (start === undefined || end === undefined) {
      throw new InvalidModelOutput(`unknown sentence id in card ${card.start_sid}..${card.end_sid}`);
    }
    if (end < start) throw new InvalidModelOutput(`reversed card ${card.start_sid}..${card.end_sid}`);
    ranges.push({ start, end, card });
  }
  ranges.sort((a, b) => a.start - b.start);
  if (ranges.length === 0) throw new InvalidModelOutput("no cards");

  // 2. Coverage: trim overlaps, attach gaps to the previous card (or the first card).
  let repairs = 0;
  let structural = 0;
  let cursor = 0;
  const fixed: typeof ranges = [];
  for (const r of ranges) {
    let start = r.start;
    if (start < cursor) {
      start = cursor;
      repairs++;
      structural++;
    }
    if (start > r.end) continue; // fully overlapped
    if (start > cursor) {
      if (fixed.length > 0) fixed[fixed.length - 1]!.end = start - 1;
      else start = cursor;
      repairs++;
      structural++;
    }
    fixed.push({ start, end: r.end, card: r.card });
    cursor = r.end + 1;
  }
  if (cursor < units.length) {
    fixed[fixed.length - 1]!.end = units.length - 1;
    repairs++;
    structural++;
  }

  const words = (s: number, e: number) => units.slice(s, e + 1).reduce((a, u) => a + u.words, 0);

  // 3. Length: merge cards under the minimum into the neighbour with the weaker boundary.
  let merged = true;
  while (merged && fixed.length > 1) {
    merged = false;
    for (let i = 0; i < fixed.length; i++) {
      const r = fixed[i]!;
      if (words(r.start, r.end) >= band.min || fixed.length === 1) continue;
      const isLast = i === fixed.length - 1;
      if (isLast && words(r.start, r.end) >= band.min * 0.5) continue; // short chapter endings are fine
      const leftScore = i > 0 ? boundaryScore(units[r.start - 1]!, units[r.start]!, breakAfter.has(r.start - 1)) : Infinity;
      const rightScore =
        i < fixed.length - 1 ? boundaryScore(units[r.end]!, units[r.end + 1]!, breakAfter.has(r.end)) : Infinity;
      if (leftScore === Infinity && rightScore === Infinity) break;
      if (leftScore <= rightScore) {
        fixed[i - 1]!.end = r.end;
        fixed.splice(i, 1);
      } else {
        fixed[i + 1]!.start = r.start;
        fixed[i + 1]!.card = { ...fixed[i + 1]!.card, title: r.card.title || fixed[i + 1]!.card.title };
        fixed.splice(i, 1);
      }
      repairs++;
      structural++;
      merged = true;
      break;
    }
  }

  // 4. Length: split cards over the maximum at the best internal boundary.
  for (let i = 0; i < fixed.length; i++) {
    const r = fixed[i]!;
    if (r.end === r.start || words(r.start, r.end) <= band.max) continue;
    let bestK = -1;
    let bestScore = Number.NEGATIVE_INFINITY;
    for (let k = r.start + 1; k <= r.end; k++) {
      const left = words(r.start, k - 1);
      const right = words(k, r.end);
      if (left < band.min * 0.6 || right < band.min * 0.6) continue;
      const balance = -Math.abs(left - right) / (left + right);
      const score = boundaryScore(units[k - 1]!, units[k]!, breakAfter.has(k - 1)) + 0.5 * balance;
      if (score > bestScore) {
        bestScore = score;
        bestK = k;
      }
    }
    if (bestK > 0) {
      fixed.splice(i + 1, 0, {
        start: bestK,
        end: r.end,
        card: { ...r.card, title: "", hook: "", key_sids: [], hard_words: [], standalone: false },
      });
      r.end = bestK - 1;
      repairs++;
      structural++;
      i--; // re-check the left part
    }
  }

  // 5. Extras: keep only references inside the card; clamp titles and hooks.
  const cards: OutCard[] = fixed.map((r) => {
    const inCard = new Set(units.slice(r.start, r.end + 1).map((u) => u.s.sid));
    const key = r.card.key_sids.filter((k) => inCard.has(k)).slice(0, 2);
    const hard = r.card.hard_words.filter((h) => {
      if (!inCard.has(h.sid)) return false;
      const sentence = units[pos.get(h.sid)!]!.s.text.toLowerCase();
      return h.word.length > 1 && sentence.includes(h.word.toLowerCase());
    });
    repairs += r.card.key_sids.length - key.length + (r.card.hard_words.length - hard.length);
    return {
      start_sid: units[r.start]!.s.sid,
      end_sid: units[r.end]!.s.sid,
      title: clampWords(r.card.title, 8) || undefined,
      hook: clampWords(r.card.hook, 14) || undefined,
      type: r.card.type || "narrative",
      standalone: r.card.standalone,
      key_sids: key,
      hard_words: hard.map((h) => ({ word: h.word, sid: h.sid, meaning: h.meaning.slice(0, 200) })),
      mood: r.card.mood && (MOODS as readonly string[]).includes(r.card.mood) ? r.card.mood : undefined,
      energy: r.card.energy === undefined ? undefined : Math.min(5, Math.max(1, Math.round(r.card.energy))),
    };
  });

  const maxAfter = cards.length - 1;
  const recaps = output.recaps
    .filter((r) => r.after_card >= 0 && r.after_card <= maxAfter && r.bullets.length > 0)
    .map((r) => ({ after_card: r.after_card, bullets: r.bullets.slice(0, 3).map((b) => b.slice(0, 240)) }));
  const recalls = output.recalls
    .filter(
      (r) =>
        r.after_card >= 0 &&
        r.after_card < maxAfter &&
        r.options.length >= 2 &&
        r.options.length <= 4 &&
        r.answer_index >= 0 &&
        r.answer_index < r.options.length,
    )
    .slice(0, Math.ceil(cards.length / LIMITS.recallEvery));

  return {
    chapter: {
      index,
      source: "ai",
      cards,
      recaps,
      recalls,
      teaser: output.chapter_teaser ? clampWords(output.chapter_teaser, 30) : undefined,
      repaired: repairs || undefined,
    },
    repairs,
    repairRate: structural / Math.max(1, output.cards.length),
  };
}

function clampWords(text: string, max: number): string {
  const words = text.trim().split(/\s+/).filter(Boolean);
  return words.length <= max ? words.join(" ") : `${words.slice(0, max).join(" ")}…`;
}

export { countWords };
