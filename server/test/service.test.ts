import { describe, expect, it, vi } from "vitest";

import type { BatchClient, BatchItemResult } from "../src/segmentation/batch.js";
import { ModelRefusal, type ChapterJob, type ModelSegmenter } from "../src/segmentation/claudeSegmenter.js";
import type { ModelOutput, SegmentRequest } from "../src/segmentation/schema.js";
import { QuotaExceeded, SegmentService, TierNotEligible } from "../src/segmentation/service.js";
import { MemoryQuotaStore, MemorySegmentCache, MemoryUsageLog } from "../src/stores/memory.js";
import { makeChapter, perfectOutput } from "./fixtures.js";

const hash = (n: number) => n.toString(16).padStart(64, "0");

function request(n = 1, chapters = [0], tier: SegmentRequest["tier"] = "plus"): SegmentRequest {
  return {
    book: { content_hash: hash(n), title: "T", author: "A", language: "en" },
    tier,
    card_length: "standard",
    reading_level: "intermediate",
    priority: "now",
    chapters: chapters.map((c) => makeChapter(c)),
  };
}

function fakeModel(answer: (job: ChapterJob) => ModelOutput | Error): ModelSegmenter & { calls: ChapterJob[] } {
  const calls: ChapterJob[] = [];
  return {
    calls,
    async segment(job) {
      calls.push(job);
      const a = answer(job);
      if (a instanceof Error) throw a;
      return { output: a, model: job.route.model, inputTokens: 5000, outputTokens: 900 };
    },
  };
}

function service(model: ModelSegmenter, batch?: BatchClient) {
  const usage = new MemoryUsageLog();
  const cache = new MemorySegmentCache();
  return { svc: new SegmentService({ cache, quota: new MemoryQuotaStore(), usage, model, batch }), usage, cache };
}

const caller = { userId: "u1" };

describe("SegmentService", () => {
  it("routes tiers to the right model and caches results", async () => {
    const model = fakeModel((job) => perfectOutput(job.chapter));
    const { svc, usage } = service(model);
    const first = await svc.segment(request(1, [0, 1], "pro"), caller);
    expect(first.chapters.map((c) => c.index)).toEqual([0, 1]);
    expect(model.calls.map((c) => [c.route.model, c.route.effort])).toEqual([
      ["claude-sonnet-5-5", "medium"],
      ["claude-sonnet-5-5", "medium"],
    ]);
    expect(usage.records[0]!.costUsd).toBeCloseTo((5000 * 2 + 900 * 10) / 1e6);
    const again = await svc.segment(request(1, [0, 1], "pro"), caller);
    expect(again.cached).toBe(2);
    expect(model.calls).toHaveLength(2);
  });

  it("the free tier is not served by the cloud", async () => {
    const { svc } = service(fakeModel((j) => perfectOutput(j.chapter)));
    await expect(svc.segment(request(1, [0], "free"), caller)).rejects.toBeInstanceOf(TierNotEligible);
  });

  it("counts a book once per month and enforces the quota", async () => {
    const { svc } = service(fakeModel((j) => perfectOutput(j.chapter)));
    for (let b = 1; b <= 8; b++) await svc.segment(request(b, [0], "pro"), caller);
    // more chapters of an already-counted book are fine
    const more = await svc.segment(request(8, [1], "pro"), caller);
    expect(more.quota).toEqual({ used: 8, limit: 8 });
    await expect(svc.segment(request(9, [0], "pro"), caller)).rejects.toBeInstanceOf(QuotaExceeded);
    // India regional quota for Pro is 5
    await expect(svc.segment(request(6, [0], "pro"), { userId: "u2", region: "IN" })).resolves.toBeDefined();
  });

  it("falls back to rules on refusal without retrying, and retries once on bad output", async () => {
    const refusing = fakeModel(() => new ModelRefusal("no"));
    const r = await service(refusing).svc.segment(request(1, [0]), caller);
    expect(r.fallback).toEqual([0]);
    expect(r.chapters).toHaveLength(0);
    expect(refusing.calls).toHaveLength(1);

    let n = 0;
    const flaky = fakeModel((job) => {
      n++;
      const out = perfectOutput(job.chapter);
      if (n === 1) out.cards[1]!.end_sid = "c0.b99.s9"; // hallucinated id
      return out;
    });
    const ok = await service(flaky).svc.segment(request(1, [0]), caller);
    expect(ok.chapters).toHaveLength(1);
    expect(flaky.calls).toHaveLength(2);
  });

  it("rejects answers that need too many repairs", async () => {
    const sloppy = fakeModel((job) => {
      const out = perfectOutput(job.chapter, 2); // 30-word cards: most need merging
      return out;
    });
    const r = await service(sloppy).svc.segment(request(1, [0]), caller);
    expect(r.fallback).toEqual([0]);
    expect(sloppy.calls).toHaveLength(2);
  });

  it("background chapters go through the Batch API at half price", async () => {
    const results: BatchItemResult[] = [];
    let status: "in_progress" | "ended" = "in_progress";
    const batch: BatchClient = {
      create: vi.fn(async (items) => {
        for (const i of items) {
          results.push({ customId: i.customId, text: JSON.stringify(perfectOutput(i.job.chapter)), model: "claude-haiku-5-5", inputTokens: 1000, outputTokens: 100 });
        }
        expect(items.every((i: { job: ChapterJob }) => i.job.route.serverFallback === false)).toBe(true);
        return "batch_1";
      }),
      status: async () => status,
      results: async () => results,
    };
    const { svc, usage, cache } = service(fakeModel((j) => perfectOutput(j.chapter)), batch);
    const req = { ...request(1, [2, 3]), priority: "background" as const };
    const submitted = await svc.submitBackground(req, caller);
    expect("jobId" in submitted).toBe(true);
    const jobId = (submitted as { jobId: string }).jobId;
    expect((await svc.pollJob(jobId, caller))!.status).toBe("pending");
    status = "ended";
    const done = await svc.pollJob(jobId, caller);
    expect(done!.status).toBe("done");
    expect(done!.result!.chapters.map((c) => c.index)).toEqual([2, 3]);
    expect(usage.records[0]!.batch).toBe(true);
    expect(usage.records[0]!.costUsd).toBeCloseTo((1000 * 0.1 + 100 * 0.5) / 1e6 / 2);
    expect(cache.size).toBe(2);
    expect(await svc.pollJob(jobId, { userId: "someone-else" })).toBeUndefined();
  });
});
