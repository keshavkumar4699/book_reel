import Anthropic from "@anthropic-ai/sdk";
import { describe, expect, it } from "vitest";

import { quotaFor, routeFor, type Tier } from "../src/config.js";
import { ClaudeSegmenter, ModelFailure, ModelRefusal } from "../src/segmentation/claudeSegmenter.js";
import { makeChapter, presentationOutput, structureOutput } from "./fixtures.js";

function message(text: string, stop: string = "end_turn", model = "claude-haiku-5-5") {
  return { content: [{ type: "text", text }], stop_reason: stop, model, usage: { input_tokens: 10, output_tokens: 5 } };
}

/** Mimics the SDK's `.stream(params).finalMessage()` on both namespaces. */
function fakeClient(handlers: { stream?: (p: any) => any; betaStream?: (p: any) => any }) {
  const calls: { kind: string; params: any }[] = [];
  const client = {
    messages: { stream: (p: any) => (calls.push({ kind: "messages", params: p }), { finalMessage: async () => handlers.stream!(p) }) },
    beta: { messages: { stream: (p: any) => (calls.push({ kind: "beta", params: p }), { finalMessage: async () => handlers.betaStream!(p) }) } },
  } as unknown as Anthropic;
  return { client, calls };
}

const job = (tier: Exclude<Tier, "free">) => ({
  title: "T",
  author: "A",
  chapter: makeChapter(),
  length: "snack" as const,
  level: "intermediate" as const,
  route: routeFor(tier)!,
});

describe("ClaudeSegmenter", () => {
  it("pass 1 on Haiku: low effort, structured output, cached system prompt, streamed", async () => {
    const { client, calls } = fakeClient({ stream: () => message(JSON.stringify(structureOutput(makeChapter()))) });
    const res = await new ClaudeSegmenter(client).structure(job("lite"));
    expect(res.output.cards).toHaveLength(6);
    const p = calls[0]!.params;
    expect(calls[0]!.kind).toBe("messages");
    expect(p.model).toBe("claude-haiku-5-5");
    expect(p.output_config.effort).toBe("low");
    expect(p.output_config.format.type).toBe("json_schema");
    expect(p.output_config.format.schema.properties.scene.enum).toContain("meadow");
    expect(p.system[0].cache_control).toEqual({ type: "ephemeral" });
    expect(p.max_tokens).toBe(64000);
    expect(p.thinking).toBeUndefined();
    expect(p.temperature).toBeUndefined();
  });

  it("each paid tier steps up one model, with quotas that keep a margin", () => {
    expect(routeFor("free")).toBeNull();
    expect(routeFor("lite")).toEqual({ model: "claude-haiku-5-5", effort: "low", serverFallback: false });
    expect(routeFor("plus")).toEqual({ model: "claude-sonnet-5-5", effort: "medium", serverFallback: true });
    expect(routeFor("pro")).toEqual({ model: "claude-opus-5-5", effort: "medium", serverFallback: true });
    expect(routeFor("pro", { dense: true })!.effort).toBe("high");
    expect(routeFor("scholar")).toEqual({ model: "claude-fable-5-2", effort: "medium", serverFallback: true });
    const quotas = (["lite", "plus", "pro", "scholar"] as const).map((t) => [quotaFor(t, "US"), quotaFor(t, "in")]);
    expect(quotas).toEqual([[12, 8], [6, 4], [6, 4], [6, 3]]);
    expect(quotaFor("free", "US")).toBe(0);
  });

  it("pass 1 on Opus uses the server-side refusal fallback", async () => {
    const { client, calls } = fakeClient({ betaStream: () => message(JSON.stringify(structureOutput(makeChapter())), "end_turn", "claude-opus-5-5") });
    await new ClaudeSegmenter(client).structure(job("pro"));
    expect(calls[0]!.kind).toBe("beta");
    expect(calls[0]!.params.model).toBe("claude-opus-5-5");
    expect(calls[0]!.params.fallbacks).toBe("default");
    expect(calls[0]!.params.betas).toEqual(["server-side-fallback-2026-07-01"]);
  });

  it("Scholar runs on Fable 5.2: thinking left to the model, effort set, refusal fallback on", async () => {
    const { client, calls } = fakeClient({ betaStream: () => message(JSON.stringify(structureOutput(makeChapter())), "end_turn", "claude-fable-5-2") });
    const res = await new ClaudeSegmenter(client).structure(job("scholar"));
    expect(res.model).toBe("claude-fable-5-2");
    const p = calls[0]!.params;
    expect(calls[0]!.kind).toBe("beta");
    expect(p.model).toBe("claude-fable-5-2");
    // Fable's thinking is always on: any explicit `thinking` setting other than adaptive is a 400.
    expect(p.thinking).toBeUndefined();
    expect(p.tool_choice).toBeUndefined();
    expect(p.output_config.effort).toBe("medium");
    expect(p.output_config.format.type).toBe("json_schema");
    expect(p.fallbacks).toBe("default");
  });

  it("retries a Haiku pass-1 refusal once on Sonnet", async () => {
    const { client, calls } = fakeClient({
      stream: () => message("", "refusal"),
      betaStream: () => message(JSON.stringify(structureOutput(makeChapter())), "end_turn", "claude-sonnet-5-5"),
    });
    const res = await new ClaudeSegmenter(client).structure(job("lite"));
    expect(res.model).toBe("claude-sonnet-5-5");
    expect(calls.map((c) => c.kind)).toEqual(["messages", "beta"]);
  });

  it("pass 2 always runs on the fast model, even for Scholar", async () => {
    const ch = makeChapter();
    const cards = [{ index: 0, sentences: ch.sentences.slice(0, 8) }];
    const { client, calls } = fakeClient({ stream: () => message(JSON.stringify(presentationOutput(cards))) });
    const res = await new ClaudeSegmenter(client).present({ title: "T", author: "A", chapterIndex: 0, chapterTitle: "C", level: "advanced", cards });
    expect(res.output.cards[0]!.emphasis[0]!.text).toBe("quiet power");
    expect(calls[0]!.params.model).toBe("claude-haiku-5-5");
    expect(calls[0]!.params.output_config.format.schema.properties.cards.items.properties.layout.enum).toEqual(["centered", "left", "staggered"]);
  });

  it("reports refusals, truncation and invalid JSON as typed errors", async () => {
    const refusal = fakeClient({ betaStream: () => message("", "refusal", "claude-sonnet-5-5") });
    await expect(new ClaudeSegmenter(refusal.client).structure(job("plus"))).rejects.toBeInstanceOf(ModelRefusal);
    const truncated = fakeClient({ stream: () => message("{", "max_tokens") });
    await expect(new ClaudeSegmenter(truncated.client).structure(job("lite"))).rejects.toBeInstanceOf(ModelFailure);
    const junk = fakeClient({ stream: () => message("not json") });
    await expect(new ClaudeSegmenter(junk.client).structure(job("lite"))).rejects.toBeInstanceOf(ModelFailure);
  });
});
