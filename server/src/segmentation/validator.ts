import { LAYOUTS, LENGTH_BANDS, LIMITS, MOODS, SCENES, type CardLength } from "../config.js";
import { boundaryScore, countWords, SCENE_BREAK, startsWithBackReference, toUnits } from "./ruleSegmenter.js";
import type {
  Emphasis,
  MusicCue,
  OutCard,
  OutChapter,
  PresentationOutput,
  SceneCue,
  Sentence,
  StructureOutput,
} from "./schema.js";

export class InvalidModelOutput extends Error {}

export interface StructureResult {
  chapter: OutChapter;
  /** Number of repairs applied (missing first card, merges, splits, dropped extras). */
  repairs: number;
  /** Share of cards that needed a structural repair. */
  repairRate: number;
}

const isMood = (m: string) => (MOODS as readonly string[]).includes(m);
const isScene = (s: string) => (SCENES as readonly string[]).includes(s);
const clampEnergy = (e: number) => Math.min(5, Math.max(1, Math.round(e)));

/**
 * Validates and repairs pass 1 (DESIGN.md §4.2). Enforces in code what the
 * model is only asked to do: every sentence in exactly one card, in order,
 * cards inside the length band. Recaps, recalls and cues that point at the
 * model's card numbers are remapped onto the repaired cards. Throws
 * [InvalidModelOutput] for unknown sentence IDs (a hallucinated answer).
 */
export function validateStructure(index: number, sentences: Sentence[], out: StructureOutput, length: CardLength): StructureResult {
  const band = LENGTH_BANDS[length];
  const { units, breakAfter } = toUnits(sentences);
  if (units.length === 0) throw new InvalidModelOutput("chapter has no sentences");
  const pos = new Map(units.map((u, i) => [u.s.sid, i]));
  const sceneSids = new Set(sentences.filter((s) => s.text === SCENE_BREAK).map((s) => s.sid));

  // 1. Model card starts → unit positions.
  const modelStarts: (number | undefined)[] = out.cards.map((c) => {
    if (sceneSids.has(c.start_sid)) return undefined;
    const p = pos.get(c.start_sid);
    if (p === undefined) throw new InvalidModelOutput(`unknown sentence id ${c.start_sid}`);
    return p;
  });
  const defined = modelStarts.filter((p): p is number => p !== undefined);
  if (defined.length === 0) throw new InvalidModelOutput("no cards");

  let repairs = 0;
  for (let i = 1; i < defined.length; i++) if (defined[i]! <= defined[i - 1]!) repairs++; // out of order / duplicate
  const starts = [...new Set(defined)].sort((a, b) => a - b);
  if (starts[0] !== 0) {
    starts.unshift(0);
    repairs++;
  }
  const ranges = starts.map((s, i) => ({ start: s, end: (starts[i + 1] ?? units.length) - 1 }));
  const words = (s: number, e: number) => units.slice(s, e + 1).reduce((a, u) => a + u.words, 0);

  // 2. Merge cards under the minimum into the neighbour with the weaker boundary.
  let merged = true;
  while (merged && ranges.length > 1) {
    merged = false;
    for (let i = 0; i < ranges.length; i++) {
      const r = ranges[i]!;
      const w = words(r.start, r.end);
      if (w >= band.min) continue;
      if (i === ranges.length - 1 && w >= band.min * 0.5) continue; // short chapter endings are fine
      const left = i > 0 ? boundaryScore(units[r.start - 1]!, units[r.start]!, breakAfter.has(r.start - 1)) : Infinity;
      const right = i < ranges.length - 1 ? boundaryScore(units[r.end]!, units[r.end + 1]!, breakAfter.has(r.end)) : Infinity;
      if (left === Infinity && right === Infinity) break;
      if (left <= right) ranges[i - 1]!.end = r.end;
      else ranges[i + 1]!.start = r.start;
      ranges.splice(i, 1);
      repairs++;
      merged = true;
      break;
    }
  }

  // 3. Split cards over the maximum at the best internal boundary.
  for (let i = 0; i < ranges.length; i++) {
    const r = ranges[i]!;
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
      ranges.splice(i + 1, 0, { start: bestK, end: r.end });
      r.end = bestK - 1;
      repairs++;
      i--; // re-check the left part
    }
  }
  const structural = repairs;

  const cards: OutCard[] = ranges.map((r) => ({
    start_sid: units[r.start]!.s.sid,
    end_sid: units[r.end]!.s.sid,
    type: "narrative",
    standalone: !startsWithBackReference(units[r.start]!.s.text),
    key_sids: [],
    hard_words: [],
  }));

  // 4. Remap the model's card numbers onto the repaired cards.
  const cardOfUnit = (u: number) => ranges.findIndex((r) => u >= r.start && u <= r.end);
  const startUnitOf = (k: number): number | undefined => {
    if (k < 0 || modelStarts.length === 0) return undefined;
    return modelStarts[Math.min(k, modelStarts.length - 1)];
  };
  const endUnitOf = (k: number): number | undefined => {
    if (k < 0) return undefined;
    for (let j = k + 1; j < modelStarts.length; j++) {
      const next = modelStarts[j];
      if (next !== undefined) return next - 1;
    }
    return units.length - 1;
  };
  const atCard = (k: number) => {
    const u = startUnitOf(k);
    return u === undefined ? undefined : cardOfUnit(u);
  };
  const afterCard = (k: number) => {
    const u = endUnitOf(k);
    return u === undefined ? undefined : cardOfUnit(u);
  };
  const last = cards.length - 1;

  const recaps = out.recaps
    .map((r) => ({ after_card: afterCard(r.after_card), bullets: r.bullets.slice(0, 3).map((b) => b.slice(0, 240)) }))
    .filter((r): r is { after_card: number; bullets: string[] } => r.after_card !== undefined && r.after_card >= 0 && r.bullets.length > 0);
  const recalls = out.recalls
    .filter((r) => r.options.length >= 2 && r.options.length <= 4 && r.answer_index >= 0 && r.answer_index < r.options.length)
    .map((r) => ({ ...r, after_card: afterCard(r.after_card) }))
    .filter((r): r is typeof r & { after_card: number } => r.after_card !== undefined && r.after_card >= 0 && r.after_card < last)
    .slice(0, Math.max(1, Math.ceil(cards.length / LIMITS.recallEvery)));

  const scene = isScene(out.scene) ? out.scene : undefined;
  const sceneCues: SceneCue[] = [];
  for (const c of [...out.scene_cues].sort((a, b) => a.at_card - b.at_card)) {
    const at = atCard(c.at_card);
    if (at === undefined || at <= 0 || !isScene(c.scene)) continue;
    const previous = sceneCues.at(-1)?.scene ?? scene;
    if (previous === c.scene || sceneCues.some((x) => x.at_card === at)) continue;
    sceneCues.push({ at_card: at, scene: c.scene });
  }

  const musicCues: MusicCue[] = [];
  for (const c of [...out.music_cues].sort((a, b) => a.at_card - b.at_card)) {
    let at = atCard(c.at_card);
    if (at === undefined || !isMood(c.mood)) continue;
    if (musicCues.length === 0) at = 0; // the score always starts with the chapter
    const energy = clampEnergy(c.energy);
    const previous = musicCues.at(-1);
    if (previous && (previous.at_card === at || (previous.mood === c.mood && previous.energy === energy))) continue;
    musicCues.push({ at_card: at, mood: c.mood, energy, description: c.description.trim().slice(0, 80) });
  }

  const extras =
    out.recaps.length - recaps.length +
    (out.recalls.length - recalls.length) +
    (out.scene_cues.length - sceneCues.length) +
    (out.music_cues.length - musicCues.length);

  return {
    chapter: {
      index,
      source: "ai",
      cards,
      recaps,
      recalls,
      teaser: out.chapter_teaser ? clampWords(out.chapter_teaser, 30) : undefined,
      scene,
      scene_cues: sceneCues.slice(0, LIMITS.maxSceneCues),
      music_cues: musicCues.slice(0, LIMITS.maxMusicCues),
      repaired: repairs + extras || undefined,
    },
    repairs: repairs + extras,
    repairRate: structural / Math.max(1, out.cards.length),
  };
}

/** Sentence IDs of each card, in order (scene-break markers excluded). */
export function cardSentences(chapter: OutChapter, sentences: Sentence[]): Sentence[][] {
  const content = sentences.filter((s) => s.text !== SCENE_BREAK);
  const pos = new Map(content.map((s, i) => [s.sid, i]));
  return chapter.cards.map((c) => content.slice(pos.get(c.start_sid)!, pos.get(c.end_sid)! + 1));
}

export interface PresentationResult {
  chapter: OutChapter;
  applied: number;
  dropped: number;
}

/**
 * Validates pass 2 (art direction) and merges it into the cards. Emphasised
 * phrases must appear verbatim (case-insensitive) in their sentence, belong
 * to that card and not overlap; at most one hero (level 3) and three
 * phrases per card. Anything that fails is dropped, never guessed.
 */
export function applyPresentation(chapter: OutChapter, sentences: Sentence[], out: PresentationOutput): PresentationResult {
  const perCard = cardSentences(chapter, sentences);
  const text = new Map(sentences.map((s) => [s.sid, s.text]));
  const cards = [...chapter.cards];
  let applied = 0;
  let dropped = 0;
  for (const p of out.cards) {
    if (p.card < 0 || p.card >= cards.length) {
      dropped++;
      continue;
    }
    const sids = new Set(perCard[p.card]!.map((s) => s.sid));
    const emphasis: (Emphasis & { start: number; end: number })[] = [];
    let hero = false;
    for (const e of p.emphasis) {
      const sentence = text.get(e.sid);
      const phrase = e.text.trim();
      const wordCount = countWords(phrase);
      if (!sentence || !sids.has(e.sid) || (e.level !== 2 && e.level !== 3) || wordCount === 0 || wordCount > 14) {
        dropped++;
        continue;
      }
      const at = sentence.toLowerCase().indexOf(phrase.toLowerCase());
      if (at < 0 || phrase.length >= sentence.length * 0.95) {
        dropped++; // not in the text, or the whole sentence
        continue;
      }
      const end = at + phrase.length;
      if (emphasis.some((x) => x.sid === e.sid && at < x.end && end > x.start)) {
        dropped++;
        continue;
      }
      let level = e.level;
      if (level === 3 && (hero || wordCount > 8)) level = 2;
      if (level === 3) hero = true;
      emphasis.push({ sid: e.sid, text: sentence.slice(at, end), level, start: at, end });
    }
    const mood = isMood(p.mood) ? p.mood : undefined;
    cards[p.card] = {
      ...cards[p.card]!,
      emphasis: emphasis.slice(0, 3).map(({ sid, text: t, level }) => ({ sid, text: t, level })),
      layout: (LAYOUTS as readonly string[]).includes(p.layout) ? p.layout : undefined,
      key_sids: p.key_sids.filter((s) => sids.has(s)).slice(0, 2),
      mood,
      energy: mood ? clampEnergy(p.energy) : undefined,
      hard_words: p.hard_words
        .filter((h) => sids.has(h.sid) && h.word.length > 1 && (text.get(h.sid) ?? "").toLowerCase().includes(h.word.toLowerCase()))
        .slice(0, 4)
        .map((h) => ({ word: h.word, sid: h.sid, meaning: h.meaning.slice(0, 200) })),
    };
    applied++;
  }
  return { chapter: { ...chapter, cards, presented: (chapter.presented ?? 0) + applied }, applied, dropped };
}

function clampWords(text: string, max: number): string {
  const words = text.trim().split(/\s+/).filter(Boolean);
  return words.length <= max ? words.join(" ") : `${words.slice(0, max).join(" ")}…`;
}

export { countWords };
