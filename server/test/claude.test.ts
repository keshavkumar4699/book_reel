import Anthropic from "@anthropic-ai/sdk";
import { describe, expect, it } from "vitest";

import { routeFor } from "../src/config.js";
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

const job = (tier: "plus" | "pro" | "scholar") => ({
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
    const res = await new ClaudeSegmenter(client).structure(job("plus"));
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

  it("pass 1 on Opus uses the server-side refusal fallback", async () => {
    const { client, calls } = fakeClient({ betaStream: () => message(JSON.stringify(structureOutput(makeChapter())), "end_turn", "claude-opus-5-5") });
    await new ClaudeSegmenter(client).structure(job("scholar"));
    expect(calls[0]!.kind).toBe("beta");
    expect(calls[0]!.params.model).toBe("claude-opus-5-5");
    expect(calls[0]!.params.fallbacks).toBe("default");
    expect(calls[0]!.params.betas).toEqual(["server-side-fallback-2026-07-01"]);
  });

  it("retries a Haiku pass-1 refusal once on Sonnet", async () => {
    const { client, calls } = fakeClient({
      stream: () => message("", "refusal"),
      betaStream: () => message(JSON.stringify(structureOutput(makeChapter())), "end_turn", "claude-sonnet-5-5"),
    });
    const res = await new ClaudeSegmenter(client).structure(job("plus"));
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
    await expect(new ClaudeSegmenter(refusal.client).structure(job("pro"))).rejects.toBeInstanceOf(ModelRefusal);
    const truncated = fakeClient({ stream: () => message("{", "max_tokens") });
    await expect(new ClaudeSegmenter(truncated.client).structure(job("plus"))).rejects.toBeInstanceOf(ModelFailure);
    const junk = fakeClient({ stream: () => message("not json") });
    await expect(new ClaudeSegmenter(junk.client).structure(job("plus"))).rejects.toBeInstanceOf(ModelFailure);
  });
});
