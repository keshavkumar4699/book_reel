import Anthropic from "@anthropic-ai/sdk";

import { MODELS, type CardLength, type ReadingLevel, type TierRoute } from "../config.js";
import { buildUserPrompt, SYSTEM_PROMPT } from "./prompt.js";
import { MODEL_OUTPUT_JSON_SCHEMA, ModelOutputSchema, type ChapterInput, type ModelOutput } from "./schema.js";

export interface ChapterJob {
  title: string;
  author: string;
  chapter: ChapterInput;
  length: CardLength;
  level: ReadingLevel;
  route: TierRoute;
}

export interface ModelResult {
  output: ModelOutput;
  model: string;
  inputTokens: number;
  outputTokens: number;
}

export class ModelRefusal extends Error {}
export class ModelFailure extends Error {}

/** Abstraction so the service can be tested without network access. */
export interface ModelSegmenter {
  segment(job: ChapterJob): Promise<ModelResult>;
}

const MAX_TOKENS = 16000;

/** Request parameters shared by real-time and batch calls. */
export function buildParams(job: ChapterJob) {
  return {
    model: job.route.model,
    max_tokens: MAX_TOKENS,
    system: [{ type: "text" as const, text: SYSTEM_PROMPT, cache_control: { type: "ephemeral" as const } }],
    messages: [{ role: "user" as const, content: buildUserPrompt(job) }],
    output_config: {
      effort: job.route.effort,
      format: { type: "json_schema" as const, schema: MODEL_OUTPUT_JSON_SCHEMA as unknown as Record<string, unknown> },
    },
  };
}

/** Extracts and validates the JSON answer from a message's text blocks. */
export function parseModelText(text: string): ModelOutput {
  let json: unknown;
  try {
    json = JSON.parse(text);
  } catch {
    throw new ModelFailure("model returned invalid JSON");
  }
  const parsed = ModelOutputSchema.safeParse(json);
  if (!parsed.success) throw new ModelFailure(`model output failed schema validation: ${parsed.error.message}`);
  return parsed.data;
}

/**
 * Real-time segmentation with Claude (DESIGN.md §4.3).
 * - Sonnet/Opus: server-side refusal fallback (`fallbacks: "default"`).
 * - Haiku: no server-side fallback, so a refusal is retried once on Sonnet.
 */
export class ClaudeSegmenter implements ModelSegmenter {
  constructor(private readonly client: Anthropic = new Anthropic()) {}

  async segment(job: ChapterJob): Promise<ModelResult> {
    try {
      return await this.call(job);
    } catch (e) {
      if (e instanceof ModelRefusal && job.route.model === MODELS.haiku) {
        return this.call({ ...job, route: { model: MODELS.sonnet, effort: "low", serverFallback: true } });
      }
      throw e;
    }
  }

  private async call(job: ChapterJob): Promise<ModelResult> {
    const params = buildParams(job);
    let message: { content: Array<{ type: string; text?: string }>; stop_reason: string | null; model: string; usage: { input_tokens: number; output_tokens: number } };
    try {
      message = job.route.serverFallback
        ? await this.client.beta.messages.create({
            ...params,
            betas: ["server-side-fallback-2026-07-01"],
            fallbacks: "default",
          })
        : await this.client.messages.create(params);
    } catch (e) {
      if (e instanceof Anthropic.RateLimitError) throw new ModelFailure("rate limited");
      if (e instanceof Anthropic.APIError) throw new ModelFailure(`Claude API error ${e.status}: ${e.message}`);
      throw e;
    }
    if (message.stop_reason === "refusal") throw new ModelRefusal("model declined this chapter");
    if (message.stop_reason === "max_tokens") throw new ModelFailure("output truncated at max_tokens");
    const text = message.content
      .filter((b) => b.type === "text")
      .map((b) => b.text ?? "")
      .join("");
    return {
      output: parseModelText(text),
      model: message.model,
      inputTokens: message.usage.input_tokens,
      outputTokens: message.usage.output_tokens,
    };
  }
}
