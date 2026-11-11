/**
 * Tier → model routing and quotas (DESIGN.md §4.3 and §6).
 * Model IDs are pinned here so upgrades are deliberate and evaluated.
 */
export type Tier = "free" | "plus" | "pro" | "scholar";
export type CardLength = "snack" | "bite" | "standard" | "deep";
export type ReadingLevel = "beginner" | "intermediate" | "advanced";
export type Effort = "low" | "medium" | "high";

export const MODELS = {
  haiku: "claude-haiku-5-5",
  sonnet: "claude-sonnet-5-5",
  opus: "claude-opus-5-5",
} as const;

export type ModelId = (typeof MODELS)[keyof typeof MODELS];

export interface TierRoute {
  model: ModelId;
  effort: Effort;
  /** Server-side refusal fallback is available on Sonnet/Opus (Claude API only). */
  serverFallback: boolean;
}

export function routeFor(tier: Tier, opts: { dense?: boolean } = {}): TierRoute | null {
  switch (tier) {
    case "free":
      return null; // on-device rules (and later an on-device open model)
    case "plus":
      return { model: MODELS.haiku, effort: "low", serverFallback: false };
    case "pro":
      return { model: MODELS.sonnet, effort: "medium", serverFallback: true };
    case "scholar":
      return { model: MODELS.opus, effort: opts.dense ? "high" : "medium", serverFallback: true };
  }
}

/** Card length bands in words; must match app/lib/core/segmentation/rule_segmenter.dart. */
export const LENGTH_BANDS: Record<CardLength, { min: number; target: number; max: number }> = {
  snack: { min: 12, target: 30, max: 55 },
  bite: { min: 45, target: 75, max: 110 },
  standard: { min: 70, target: 120, max: 180 },
  deep: { min: 120, target: 180, max: 240 },
};

/**
 * Monthly AI-book quotas by tier and region (DESIGN.md §6). Lower than v1
 * because each book now also gets per-card art direction, scenes and a
 * soundtrack plan (see the cost model in DESIGN.md §5).
 */
export const QUOTAS: Record<Exclude<Tier, "free">, { default: number; IN: number }> = {
  plus: { default: 12, IN: 8 },
  pro: { default: 6, IN: 4 },
  scholar: { default: 6, IN: 4 },
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
