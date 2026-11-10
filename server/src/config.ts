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

/** Monthly AI-book quotas by tier and region (DESIGN.md §6.1–6.2). */
export const QUOTAS: Record<Exclude<Tier, "free">, { default: number; IN: number }> = {
  plus: { default: 20, IN: 20 },
  pro: { default: 8, IN: 5 },
  scholar: { default: 8, IN: 5 },
};

export function quotaFor(tier: Tier, region: string | undefined): number {
  if (tier === "free") return 0;
  const q = QUOTAS[tier];
  return region?.toUpperCase() === "IN" ? q.IN : q.default;
}

/** Bump when prompts or validation change so cached segment maps are rebuilt. */
export const SEGMENTER_VERSION = "seg-v1";

export const LIMITS = {
  maxChaptersPerRequest: 3,
  maxSentencesPerChapter: 4000,
  /** Keep Haiku requests well under its 100K-token price threshold. */
  maxChapterChars: 160_000,
  recallEvery: 10,
};
