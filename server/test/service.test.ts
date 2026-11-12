import { describe, expect, it, vi } from "vitest";

import type { BatchClient, BatchItemResult } from "../src/segmentation/batch.js";
import { ModelFailure, ModelRefusal, type ModelSegmenter, type PresentationJob, type StructureJob } from "../src/segmentation/claudeSegmenter.js";
import type { PresentationOutput, SegmentRequest, StructureOutput } from "../src/segmentation/schema.js";
import { QuotaExceeded, SegmentService, TierNotEligible } from "../src/segmentation/service.js";
import { MemoryQuotaStore, MemorySegmentCache, MemoryUsageLog } from "../src/stores/memory.js";
import { makeChapter, presentationOutput, structureOutput } from "./fixtures.js";

const hash = (n: number) => n.toString(16).padStart(64, "0");

function request(n = 1, chapters = [0], tier: SegmentRequest["tier"] = "lite", card_length: SegmentRequest["card_length"] = "standard"): SegmentRequest {
  return {
    book: { content_hash: hash(n), title: "T", author: "A", language: "en" },
    tier,
    card_length,
    reading_level: "intermediate",
    priority: "now",
    chapters: chapters.map((c) => makeChapter(c)),
  };
}

function fakeModel(opts: {
  structure?: (job: StructureJob) => StructureOutput | Error;
  present?: (job: PresentationJob) => PresentationOutput | Error;
} = {}): ModelSegmenter & { structureCalls: StructureJob[]; presentCalls: PresentationJob[] } {
  const structureCalls: StructureJob[] = [];
  const presentCalls: PresentationJob[] = [];
  return {
    structureCalls,
    presentCalls,
    async structure(job) {
      structureCalls.push(job);
      const a = (opts.structure ?? ((j) => structureOutput(j.chapter)))(job);
      if (a instanceof Error) throw a;
      return { output: a, model: job.route.model, inputTokens: 5000, outputTokens: 900 };
    },
    async present(job) {
      presentCalls.push(job);
      const a = (opts.present ?? ((j) => presentationOutput(j.cards)))(job);
      if (a instanceof Error) throw a;
      return { output: a, model: "claude-haiku-5-5", inputTokens: 3000, outputTokens: 1200 };
    },
  };
}

function service(model: ModelSegmenter, batch?: BatchClient) {
  const usage = new MemoryUsageLog();
  const cache = new MemorySegmentCache();
  return { svc: new SegmentService({ cache, quota: new MemoryQuotaStore(), usage, model, batch }), usage, cache };
}

const caller = { userId: "u1" };

describe("SegmentService (two-pass)", () => {
  it("runs structure on the tier model, art direction on the fast model, and caches", async () => {
    const model = fakeModel();
    const { svc, usage } = service(model);
    const first = await svc.segment(request(1, [0, 1], "plus"), caller);
    expect(first.chapters.map((c) => c.index)).toEqual([0, 1]);
    expect(model.structureCalls.map((c) => [c.route.model, c.route.effort])).toEqual([
      ["claude-sonnet-5-5", "medium"],
      ["claude-sonnet-5-5", "medium"],
    ]);
    expect(model.presentCalls).toHaveLength(2);
    const ch = first.chapters[0]!;
    expect(ch.scene).toBe("forest");
    expect(ch.presented).toBe(6);
    expect(ch.cards[0]!.emphasis).toEqual([{ sid: "c0.b0.s0", text: "quiet power", level: 3 }]);
    // Usage: two Sonnet structure calls + two Haiku art-direction calls.
    expect(usage.records.map((r) => r.model).sort()).toEqual(["claude-haiku-5-5", "claude-haiku-5-5", "claude-sonnet-5-5", "claude-sonnet-5-5"]);
    expect(usage.records.find((r) => r.model === "claude-haiku-5-5")!.costUsd).toBeCloseTo((3000 * 0.1 + 1200 * 0.5) / 1e6);
    const again = await svc.segment(request(1, [0, 1], "plus"), caller);
    expect(again.cached).toBe(2);
    expect(model.structureCalls).toHaveLength(2);
  });

  it("sends art direction in batches of at most 60 cards", async () => {
    const model = fakeModel({ structure: (j) => structureOutput(j.chapter, 1) }); // one card per sentence
    const big = { ...request(1, [0], "lite", "snack"), chapters: [makeChapter(0, 40, 4)] }; // 160 sentences
    const { svc } = service(model);
    const res = await svc.segment(big, caller);
    expect(model.presentCalls.map((c) => c.cards.length)).toEqual([60, 60, 40]);
    expect(model.presentCalls[1]!.cards[0]!.index).toBe(60);
    expect(res.chapters[0]!.presented).toBe(160);
  });

  it("keeps a good chapter when art direction fails", async () => {
    const model = fakeModel({ present: () => new ModelRefusal("no") });
    const res = await service(model).svc.segment(request(1, [0]), caller);
    expect(res.chapters).toHaveLength(1);
    expect(res.chapters[0]!.cards[0]!.emphasis).toBeUndefined();
    expect(res.fallback).toEqual([]);
  });

  it("the free tier is not served by the cloud", async () => {
    await expect(service(fakeModel()).svc.segment(request(1, [0], "free"), caller)).rejects.toBeInstanceOf(TierNotEligible);
  });

  it("counts a book once per month and enforces the quota", async () => {
    const { svc } = service(fakeModel());
    for (let b = 1; b <= 6; b++) await svc.segment(request(b, [0], "pro"), caller);
    const more = await svc.segment(request(6, [1], "pro"), caller);
    expect(more.quota).toEqual({ used: 6, limit: 6 });
    await expect(svc.segment(request(7, [0], "pro"), caller)).rejects.toBeInstanceOf(QuotaExceeded);
    // Books someone already had processed come from the cache and are free.
    const india = { userId: "u2", region: "IN" };
    expect((await svc.segment(request(1, [0], "pro"), india)).cached).toBe(1);
    // India regional quota for Pro is 4 new books.
    for (let b = 11; b <= 14; b++) await svc.segment(request(b, [0], "pro"), india);
    await expect(svc.segment(request(15, [0], "pro"), india)).rejects.toBeInstanceOf(QuotaExceeded);
  });

  it("falls back to rules on refusal without retrying, and retries once on bad output", async () => {
    const refusing = fakeModel({ structure: () => new ModelRefusal("no") });
    const r = await service(refusing).svc.segment(request(1, [0]), caller);
    expect(r.fallback).toEqual([0]);
    expect(refusing.structureCalls).toHaveLength(1);
    expect(refusing.presentCalls).toHaveLength(0);

    let n = 0;
    const flaky = fakeModel({
      structure: (job) => {
        n++;
        if (n === 1) return new ModelFailure("bad json");
        return structureOutput(job.chapter);
      },
    });
    const ok = await service(flaky).svc.segment(request(1, [0]), caller);
    expect(ok.chapters).toHaveLength(1);
    expect(flaky.structureCalls).toHaveLength(2);
  });

  it("background chapters: pass 1 via the Batch API at half price, then art direction", async () => {
    const results: BatchItemResult[] = [];
    let status: "in_progress" | "ended" = "in_progress";
    const batch: BatchClient = {
      create: vi.fn(async (items) => {
        for (const i of items) {
          results.push({ customId: i.customId, text: JSON.stringify(structureOutput(i.job.chapter)), model: "claude-haiku-5-5", inputTokens: 1000, outputTokens: 100 });
        }
        expect(items.every((i: { job: StructureJob }) => i.job.route.serverFallback === false)).toBe(true);
        return "batch_1";
      }),
      status: async () => status,
      results: async () => results,
    };
    const model = fakeModel();
    const { svc, usage, cache } = service(model, batch);
    const submitted = await svc.submitBackground({ ...request(1, [2, 3]), priority: "background" }, caller);
    const jobId = (submitted as { jobId: string }).jobId;
    expect((await svc.pollJob(jobId, caller))!.status).toBe("pending");
    status = "ended";
    const done = await svc.pollJob(jobId, caller);
    expect(done!.status).toBe("done");
    expect(done!.result!.chapters.map((c) => c.index)).toEqual([2, 3]);
    expect(done!.result!.chapters[0]!.presented).toBe(6);
    const batchRecord = usage.records.find((r) => r.batch)!;
    expect(batchRecord.costUsd).toBeCloseTo((1000 * 0.1 + 100 * 0.5) / 1e6 / 2);
    expect(model.structureCalls).toHaveLength(0);
    expect(model.presentCalls).toHaveLength(2);
    expect(cache.size).toBe(2);
    expect(await svc.pollJob(jobId, { userId: "someone-else" })).toBeUndefined();
  });
});
