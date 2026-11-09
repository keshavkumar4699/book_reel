import Anthropic from "@anthropic-ai/sdk";

import { buildParams, type ChapterJob } from "./claudeSegmenter.js";

export type BatchStatus = "in_progress" | "canceling" | "ended";

export interface BatchItemResult {
  customId: string;
  /** Model text when the request succeeded and was not refused. */
  text?: string;
  model?: string;
  inputTokens?: number;
  outputTokens?: number;
  error?: string;
}

/**
 * Message Batches API (50% cheaper) for background chapters (DESIGN.md §4.3).
 * Server-side fallbacks are not supported on batches, so a refused chapter
 * simply stays on rule cards.
 */
export interface BatchClient {
  create(items: { customId: string; job: ChapterJob }[]): Promise<string>;
  status(batchId: string): Promise<BatchStatus>;
  results(batchId: string): Promise<BatchItemResult[]>;
}

export class AnthropicBatchClient implements BatchClient {
  constructor(private readonly client: Anthropic = new Anthropic()) {}

  async create(items: { customId: string; job: ChapterJob }[]): Promise<string> {
    const batch = await this.client.messages.batches.create({
      requests: items.map((i) => ({ custom_id: i.customId, params: buildParams(i.job) })),
    });
    return batch.id;
  }

  async status(batchId: string): Promise<BatchStatus> {
    const batch = await this.client.messages.batches.retrieve(batchId);
    return batch.processing_status;
  }

  async results(batchId: string): Promise<BatchItemResult[]> {
    const out: BatchItemResult[] = [];
    for await (const r of await this.client.messages.batches.results(batchId)) {
      if (r.result.type === "succeeded") {
        const m = r.result.message;
        if (m.stop_reason === "refusal" || m.stop_reason === "max_tokens") {
          out.push({ customId: r.custom_id, error: m.stop_reason });
          continue;
        }
        out.push({
          customId: r.custom_id,
          text: m.content.map((b) => (b.type === "text" ? b.text : "")).join(""),
          model: m.model,
          inputTokens: m.usage.input_tokens,
          outputTokens: m.usage.output_tokens,
        });
      } else {
        out.push({ customId: r.custom_id, error: r.result.type });
      }
    }
    return out;
  }
}
