import Anthropic from "@anthropic-ai/sdk";
import type { z } from "zod";

import { MODELS, PRESENTATION_ROUTE, type CardLength, type ReadingLevel, type TierRoute } from "../config.js";
import { buildPresentationPrompt, buildStructurePrompt, PRESENTATION_SYSTEM_PROMPT, STRUCTURE_SYSTEM_PROMPT } from "./prompt.js";
import {
  PRESENTATION_JSON_SCHEMA,
  PresentationOutputSchema,
  STRUCTURE_JSON_SCHEMA,
  StructureOutputSchema,
  type ChapterInput,
  type PresentationOutput,
  type Sentence,
  type StructureOutput,
} from "./schema.js";

export interface StructureJob {
  title: string;
  author: string;
  chapter: ChapterInput;
  length: CardLength;
  level: ReadingLevel;
  route: TierRoute;
}

export interface PresentationJob {
  title: string;
  author: string;
  chapterIndex: number;
  chapterTitle: string;
  level: ReadingLevel;
  cards: { index: number; sentences: Sentence[] }[];
}

export interface ModelResult<T> {
  output: T;
  model: string;
  inputTokens: number;
  outputTokens: number;
}

export class ModelRefusal extends Error {}
export class ModelFailure extends Error {}

/** Abstraction so the service can be tested without network access. */
export interface ModelSegmenter {
  /** Pass 1: cards, recaps, recalls, teaser, scenes. */
  structure(job: StructureJob): Promise<ModelResult<StructureOutput>>;
  /** Pass 2: per-card art direction. */
  present(job: PresentationJob): Promise<ModelResult<PresentationOutput>>;
}

/** Streaming lets long chapters of short cards use a large output budget safely. */
const MAX_TOKENS = 64000;

function params(system: string, user: string, schema: object, route: TierRoute) {
  return {
    model: route.model,
    max_tokens: MAX_TOKENS,
    system: [{ type: "text" as const, text: system, cache_control: { type: "ephemeral" as const } }],
    messages: [{ role: "user" as const, content: user }],
    output_config: {
      effort: route.effort,
      format: { type: "json_schema" as const, schema: schema as unknown as Record<string, unknown> },
    },
  };
}

export const buildStructureParams = (job: StructureJob) =>
  params(STRUCTURE_SYSTEM_PROMPT, buildStructurePrompt(job), STRUCTURE_JSON_SCHEMA, job.route);

export const buildPresentationParams = (job: PresentationJob) =>
  params(PRESENTATION_SYSTEM_PROMPT, buildPresentationPrompt(job), PRESENTATION_JSON_SCHEMA, PRESENTATION_ROUTE);

/** Parses and validates the JSON answer from a message's text blocks. */
export function parseJson<T>(text: string, schema: z.ZodType<T>): T {
  let json: unknown;
  try {
    json = JSON.parse(text);
  } catch {
    throw new ModelFailure("model returned invalid JSON");
  }
  const parsed = schema.safeParse(json);
  if (!parsed.success) throw new ModelFailure(`model output failed schema validation: ${parsed.error.message}`);
  return parsed.data;
}

export const parseStructure = (text: string) => parseJson(text, StructureOutputSchema);
export const parsePresentation = (text: string) => parseJson(text, PresentationOutputSchema);

interface MessageLike {
  content: Array<{ type: string; text?: string }>;
  stop_reason: string | null;
  model: string;
  usage: { input_tokens: number; output_tokens: number };
}

/**
 * Claude calls for both passes (DESIGN.md §4.3).
 * - Sonnet/Opus: server-side refusal fallback (`fallbacks: "default"`).
 * - Haiku structure: no server-side fallback, so a refusal is retried once on Sonnet.
 */
export class ClaudeSegmenter implements ModelSegmenter {
  constructor(private readonly client: Anthropic = new Anthropic()) {}

  async structure(job: StructureJob): Promise<ModelResult<StructureOutput>> {
    try {
      return await this.call(buildStructureParams(job), job.route, parseStructure);
    } catch (e) {
      if (e instanceof ModelRefusal && job.route.model === MODELS.haiku) {
        const route: TierRoute = { model: MODELS.sonnet, effort: "low", serverFallback: true };
        return this.call(buildStructureParams({ ...job, route }), route, parseStructure);
      }
      throw e;
    }
  }

  present(job: PresentationJob): Promise<ModelResult<PresentationOutput>> {
    return this.call(buildPresentationParams(job), PRESENTATION_ROUTE, parsePresentation);
  }

  private async call<T>(p: ReturnType<typeof params>, route: TierRoute, parse: (text: string) => T): Promise<ModelResult<T>> {
    let message: MessageLike;
    try {
      message = route.serverFallback
        ? await this.client.beta.messages
            .stream({ ...p, betas: ["server-side-fallback-2026-07-01"], fallbacks: "default" })
            .finalMessage()
        : await this.client.messages.stream(p).finalMessage();
    } catch (e) {
      if (e instanceof Anthropic.RateLimitError) throw new ModelFailure("rate limited");
      if (e instanceof Anthropic.APIError) throw new ModelFailure(`Claude API error ${e.status}: ${e.message}`);
      throw e;
    }
    if (message.stop_reason === "refusal") throw new ModelRefusal("model declined this request");
    if (message.stop_reason === "max_tokens") throw new ModelFailure("output truncated at max_tokens");
    const text = message.content
      .filter((b) => b.type === "text")
      .map((b) => b.text ?? "")
      .join("");
    return {
      output: parse(text),
      model: message.model,
      inputTokens: message.usage.input_tokens,
      outputTokens: message.usage.output_tokens,
    };
  }
}
