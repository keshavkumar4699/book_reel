import Anthropic from "@anthropic-ai/sdk";
import { describe, expect, it } from "vitest";

import { routeFor } from "../src/config.js";
import { ClaudeSegmenter, ModelFailure, ModelRefusal } from "../src/segmentation/claudeSegmenter.js";
import { makeChapter, perfectOutput } from "./fixtures.js";

function message(text: string, stop: string = "end_turn", model = "claude-haiku-5-5") {
  return { content: [{ type: "text", text }], stop_reason: stop, model, usage: { input_tokens: 10, output_tokens: 5 } };
}

function fakeClient(handlers: { create?: (p: any) => any; betaCreate?: (p: any) => any }) {
  const calls: { kind: string; params: any }[] = [];
  const client = {
    messages: { create: async (p: any) => (calls.push({ kind: "messages", params: p }), handlers.create!(p)) },
    beta: { messages: { create: async (p: any) => (calls.push({ kind: "beta", params: p }), handlers.betaCreate!(p)) } },
  } as unknown as Anthropic;
  return { client, calls };
}

const job = (tier: "plus" | "pro" | "scholar") => ({
  title: "T",
  author: "A",
  chapter: makeChapter(),
  length: "standard" as const,
  level: "intermediate" as const,
  route: routeFor(tier)!,
});

describe("ClaudeSegmenter", () => {
  it("calls Haiku with low effort, structured output and a cached system prompt", async () => {
    const answer = JSON.stringify(perfectOutput(makeChapter()));
    const { client, calls } = fakeClient({ create: () => message(answer) });
    const res = await new ClaudeSegmenter(client).segment(job("plus"));
    expect(res.output.cards).toHaveLength(6);
    const p = calls[0]!.params;
    expect(calls[0]!.kind).toBe("messages");
    expect(p.model).toBe("claude-haiku-5-5");
    expect(p.output_config.effort).toBe("low");
    expect(p.output_config.format.type).toBe("json_schema");
    expect(p.system[0].cache_control).toEqual({ type: "ephemeral" });
    expect(p.thinking).toBeUndefined();
    expect(p.temperature).toBeUndefined();
  });

  it("uses server-side refusal fallback on Sonnet and Opus", async () => {
    const answer = JSON.stringify(perfectOutput(makeChapter()));
    const { client, calls } = fakeClient({ betaCreate: () => message(answer, "end_turn", "claude-opus-5-5") });
    await new ClaudeSegmenter(client).segment(job("scholar"));
    expect(calls[0]!.kind).toBe("beta");
    expect(calls[0]!.params.model).toBe("claude-opus-5-5");
    expect(calls[0]!.params.fallbacks).toBe("default");
    expect(calls[0]!.params.betas).toEqual(["server-side-fallback-2026-07-01"]);
  });

  it("retries a Haiku refusal once on Sonnet", async () => {
    const answer = JSON.stringify(perfectOutput(makeChapter()));
    const { client, calls } = fakeClient({
      create: () => message("", "refusal"),
      betaCreate: () => message(answer, "end_turn", "claude-sonnet-5-5"),
    });
    const res = await new ClaudeSegmenter(client).segment(job("plus"));
    expect(res.model).toBe("claude-sonnet-5-5");
    expect(calls.map((c) => c.kind)).toEqual(["messages", "beta"]);
  });

  it("reports refusals, truncation and invalid JSON as typed errors", async () => {
    const refusal = fakeClient({ betaCreate: () => message("", "refusal", "claude-sonnet-5-5") });
    await expect(new ClaudeSegmenter(refusal.client).segment(job("pro"))).rejects.toBeInstanceOf(ModelRefusal);
    const truncated = fakeClient({ create: () => message("{", "max_tokens") });
    await expect(new ClaudeSegmenter(truncated.client).segment(job("plus"))).rejects.toBeInstanceOf(ModelFailure);
    const junk = fakeClient({ create: () => message("not json") });
    await expect(new ClaudeSegmenter(junk.client).segment(job("plus"))).rejects.toBeInstanceOf(ModelFailure);
  });
});
