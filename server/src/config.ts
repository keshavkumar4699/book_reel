/**
 * Tier → model routing and quotas (DESIGN.md §4.3 and §6).
 * Model IDs are pinned here so upgrades are deliberate and evaluated.
 */
export type Tier = "free" | "lite" | "plus" | "pro" | "scholar";
export type CardLength = "snack" | "bite" | "standard" | "deep";
export type ReadingLevel = "beginner" | "intermediate" | "advanced";
export type Effort = "low" | "medium" | "high";

export const MODELS = {
  haiku: "claude-haiku-5-5",
  sonnet: "claude-sonnet-5-5",
  opus: "claude-opus-5-5",
  /** Most capable widely released model. Thinking is always on (no `thinking` param is sent). */
  fable: "claude-fable-5-2",
} as const;

export type ModelId = (typeof MODELS)[keyof typeof MODELS];

export interface TierRoute {
  model: ModelId;
  effort: Effort;
  /** Server-side refusal fallback is available on Sonnet, Opus and Fable (Claude API only). */
  serverFallback: boolean;
}

/**
 * One model per tier, each a step up (DESIGN.md §6.1):
 * Lite → Haiku, Plus → Sonnet, Pro → Opus, Scholar → Fable.
 * Fable stays at medium effort: it is the costliest model per token, and the
 * Scholar price is set so even a month of real-time books keeps a margin.
 */
export function routeFor(tier: Tier, opts: { dense?: boolean } = {}): TierRoute | null {
  switch (tier) {
    case "free":
      return null; // on-device rules (and later an on-device open model)
    case "lite":
      return { model: MODELS.haiku, effort: "low", serverFallback: false };
    case "plus":
      return { model: MODELS.sonnet, effort: "medium", serverFallback: true };
    case "pro":
      return { model: MODELS.opus, effort: opts.dense ? "high" : "medium", serverFallback: true };
    case "scholar":
      return { model: MODELS.fable, effort: "medium", serverFallback: true };
  }
}

/** Paid tiers, cheapest first. */
export const PAID_TIERS = ["lite", "plus", "pro", "scholar"] as const satisfies readonly Tier[];
export const isPaidTier = (tier: string): tier is Exclude<Tier, "free"> => (PAID_TIERS as readonly string[]).includes(tier);

/** Card length bands in words; must match app/lib/core/segmentation/rule_segmenter.dart. */
export const LENGTH_BANDS: Record<CardLength, { min: number; target: number; max: number }> = {
  snack: { min: 12, target: 30, max: 55 },
  bite: { min: 45, target: 75, max: 110 },
  standard: { min: 70, target: 120, max: 180 },
  deep: { min: 120, target: 180, max: 240 },
};

/**
 * Monthly AI-book quotas by tier and region (DESIGN.md §6). Set so every tier
 * keeps a margin even if every quota book is processed in real time (see the
 * cost model in DESIGN.md §5).
 */
export const QUOTAS: Record<Exclude<Tier, "free">, { default: number; IN: number }> = {
  lite: { default: 12, IN: 8 },
  plus: { default: 6, IN: 4 },
  pro: { default: 6, IN: 4 },
  scholar: { default: 6, IN: 3 },
};

export function quotaFor(tier: Tier, region: string | undefined): number {
  if (tier === "free") return 0;
  const q = QUOTAS[tier];
  return region?.toUpperCase() === "IN" ? q.IN : q.default;
}

/** Bump when prompts or validation change so cached segment maps are rebuilt. */
export const SEGMENTER_VERSION = "seg-v5"; // v5: no music cues or card moods (scenes bring their own ambient sound)

/** Background scenes the AI can choose (app/lib/ui/vibes.dart); each has its own ambient sound. */
export const SCENES = ["forest", "cafe", "rain", "ocean", "night", "meadow", "snow", "city"] as const;
export type Scene = (typeof SCENES)[number];

/** Card layouts for the full-screen lyric typography. */
export const LAYOUTS = ["centered", "left", "staggered"] as const;

/**
 * Per-card art direction (emphasis, layout, word meanings) runs on the
 * fast model for every paid tier: it is a light task and the bulk of the
 * output tokens, so this keeps cost per book low (DESIGN.md §5).
 */
export const PRESENTATION_ROUTE: TierRoute = { model: MODELS.haiku, effort: "low", serverFallback: false };

/** Book typography: one small classification per book (cached by content hash). */
export const PROFILE_ROUTE: TierRoute = { model: MODELS.haiku, effort: "low", serverFallback: false };

/** Typographic voices the app can render (app/lib/ui/typography.dart). */
export const VOICES = ["classic", "romance", "fantasy", "scifi", "suspense", "modern", "playful"] as const;
export type Voice = (typeof VOICES)[number];

export const LIMITS = {
  maxChaptersPerRequest: 3,
  maxSentencesPerChapter: 4000,
  /** Keep Haiku requests well under its 100K-token price threshold. */
  maxChapterChars: 160_000,
  recallEvery: 10,
  /** Cards per art-direction request (keeps each response well under max_tokens). */
  presentationBatch: 60,
  maxSceneCues: 3,
};
