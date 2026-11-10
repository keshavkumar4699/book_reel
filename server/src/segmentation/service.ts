import { randomUUID } from "node:crypto";

import { quotaFor, routeFor, SEGMENTER_VERSION, type CardLength, type ReadingLevel, type Tier } from "../config.js";
import type { QuotaStore, SegmentCache, UsageLog } from "../stores/memory.js";
import type { BatchClient } from "./batch.js";
import { ModelFailure, ModelRefusal, parseModelText, type ChapterJob, type ModelSegmenter } from "./claudeSegmenter.js";
import type { ChapterInput, OutChapter, SegmentRequest } from "./schema.js";
import { InvalidModelOutput, validateAndRepair } from "./validator.js";

/** Per-million-token prices (USD, Anthropic first-party, Oct 2026) for usage logging. */
const PRICES: Record<string, { input: number; output: number }> = {
  "claude-haiku-5-5": { input: 0.1, output: 0.5 },
  "claude-sonnet-5-5": { input: 2, output: 10 },
  "claude-opus-5-5": { input: 4, output: 20 },
};

export function estimateCost(model: string, inputTokens: number, outputTokens: number, batch = false): number {
  const p = PRICES[model] ?? PRICES["claude-opus-5-5"]!;
  const cost = (inputTokens * p.input + outputTokens * p.output) / 1_000_000;
  return batch ? cost / 2 : cost;
}

export interface Caller {
  userId: string;
  region?: string;
}

export class QuotaExceeded extends Error {
  constructor(readonly limit: number) {
    super(`Monthly AI book quota reached (${limit})`);
  }
}

export class TierNotEligible extends Error {}

export interface SegmentResponse {
  chapters: OutChapter[];
  cached: number;
  /** Chapters that fell back to on-device rules (refusal, failure or too many repairs). */
  fallback: number[];
  quota: { used: number; limit: number };
}

export interface BatchJob {
  id: string;
  batchId: string;
  userId: string;
  contentHash: string;
  tier: Tier;
  length: CardLength;
  level: ReadingLevel;
  /** Chapter inputs keyed by batch custom_id (`ch<index>`). */
  chapters: Record<string, ChapterInput>;
  status: "pending" | "done" | "failed";
  result?: SegmentResponse;
  createdAt: Date;
}

const MAX_REPAIR_RATE = 0.2;

export interface JobStore {
  get(id: string): Promise<BatchJob | undefined>;
  save(job: BatchJob): Promise<void>;
}

export class MemoryJobStore implements JobStore {
  private readonly jobs = new Map<string, BatchJob>();
  async get(id: string) {
    return this.jobs.get(id);
  }
  async save(job: BatchJob) {
    this.jobs.set(job.id, job);
  }
}

export class SegmentService {
  private readonly jobs: JobStore;

  constructor(
    private readonly deps: {
      cache: SegmentCache;
      quota: QuotaStore;
      usage: UsageLog;
      model: ModelSegmenter;
      batch?: BatchClient;
      jobs?: JobStore;
      now?: () => Date;
    },
  ) {
    this.jobs = deps.jobs ?? new MemoryJobStore();
  }

  private period(): string {
    return (this.deps.now?.() ?? new Date()).toISOString().slice(0, 7);
  }

  static cacheKey(hash: string, tier: Tier, length: CardLength, level: ReadingLevel, chapter: number): string {
    return `${hash}|${SEGMENTER_VERSION}|${tier}|${length}|${level}|ch${chapter}`;
  }

  /** Checks quota before any model call; a book counts once per month. */
  private async reserveQuota(caller: Caller, tier: Tier, hash: string): Promise<{ used: number; limit: number }> {
    const limit = quotaFor(tier, caller.region);
    const used = await this.deps.quota.booksUsed(caller.userId, this.period());
    if (!used.has(hash) && used.size >= limit) throw new QuotaExceeded(limit);
    return { used: used.size + (used.has(hash) ? 0 : 1), limit };
  }

  async segment(req: SegmentRequest, caller: Caller): Promise<SegmentResponse> {
    const route = routeFor(req.tier);
    if (!route) throw new TierNotEligible("The free tier uses on-device segmentation.");
    const hash = req.book.content_hash;

    const chapters: OutChapter[] = [];
    const missing: ChapterInput[] = [];
    let cached = 0;
    for (const ch of req.chapters) {
      const hit = await this.deps.cache.get(SegmentService.cacheKey(hash, req.tier, req.card_length, req.reading_level, ch.index));
      if (hit) {
        chapters.push(hit);
        cached++;
      } else {
        missing.push(ch);
      }
    }
    const used = await this.deps.quota.booksUsed(caller.userId, this.period());
    let quota = { used: used.size, limit: quotaFor(req.tier, caller.region) };
    if (missing.length === 0) return { chapters, cached, fallback: [], quota };

    quota = await this.reserveQuota(caller, req.tier, hash);
    const fallback: number[] = [];
    const results = await Promise.all(
      missing.map((chapter) =>
        this.segmentOne(
          { title: req.book.title, author: req.book.author, chapter, length: req.card_length, level: req.reading_level, route },
          caller,
        ),
      ),
    );
    let anySuccess = false;
    for (let i = 0; i < missing.length; i++) {
      const out = results[i];
      const ch = missing[i]!;
      if (!out) {
        fallback.push(ch.index);
        continue;
      }
      anySuccess = true;
      chapters.push(out);
      await this.deps.cache.set(SegmentService.cacheKey(hash, req.tier, req.card_length, req.reading_level, ch.index), out);
    }
    if (anySuccess) await this.deps.quota.addBook(caller.userId, this.period(), hash);
    chapters.sort((a, b) => a.index - b.index);
    return { chapters, cached, fallback, quota };
  }

  /** Model call → validate/repair → one retry on failure or heavy repair → null means "use rules". */
  private async segmentOne(job: ChapterJob, caller: Caller): Promise<OutChapter | null> {
    for (let attempt = 0; attempt < 2; attempt++) {
      try {
        const res = await this.deps.model.segment(job);
        await this.deps.usage.add({
          userId: caller.userId,
          model: res.model,
          inputTokens: res.inputTokens,
          outputTokens: res.outputTokens,
          costUsd: estimateCost(res.model, res.inputTokens, res.outputTokens),
          batch: false,
          at: new Date(),
        });
        const v = validateAndRepair(job.chapter.index, job.chapter.sentences, res.output, job.length);
        if (v.repairRate <= MAX_REPAIR_RATE) return v.chapter;
      } catch (e) {
        if (e instanceof ModelRefusal) return null; // retrying a refusal won't help
        if (!(e instanceof ModelFailure || e instanceof InvalidModelOutput)) throw e;
      }
    }
    return null;
  }

  // ------------------------------------------------------------------ batch

  async submitBackground(req: SegmentRequest, caller: Caller): Promise<{ jobId: string } | SegmentResponse> {
    const route = routeFor(req.tier);
    if (!route) throw new TierNotEligible("The free tier uses on-device segmentation.");
    if (!this.deps.batch) return this.segment(req, caller);
    const hash = req.book.content_hash;
    const missing: ChapterInput[] = [];
    for (const ch of req.chapters) {
      const key = SegmentService.cacheKey(hash, req.tier, req.card_length, req.reading_level, ch.index);
      if (!(await this.deps.cache.get(key))) missing.push(ch);
    }
    if (missing.length === 0) return this.segment(req, caller);
    await this.reserveQuota(caller, req.tier, hash);
    const items = missing.map((chapter) => ({
      customId: `ch${chapter.index}`,
      job: {
        title: req.book.title,
        author: req.book.author,
        chapter,
        length: req.card_length,
        level: req.reading_level,
        route: { ...route, serverFallback: false },
      },
    }));
    const batchId = await this.deps.batch.create(items);
    const job: BatchJob = {
      id: randomUUID(),
      batchId,
      userId: caller.userId,
      contentHash: hash,
      tier: req.tier,
      length: req.card_length,
      level: req.reading_level,
      chapters: Object.fromEntries(missing.map((c) => [`ch${c.index}`, c])),
      status: "pending",
      createdAt: new Date(),
    };
    await this.jobs.save(job);
    return { jobId: job.id };
  }

  /** Polls a background job; when the batch has ended, validates, caches and returns results. */
  async pollJob(jobId: string, caller: Caller): Promise<BatchJob | undefined> {
    const job = await this.jobs.get(jobId);
    if (!job || job.userId !== caller.userId || !this.deps.batch) return undefined;
    if (job.status !== "pending") return job;
    if ((await this.deps.batch.status(job.batchId)) !== "ended") return job;
    const chapters: OutChapter[] = [];
    const fallback: number[] = [];
    for (const r of await this.deps.batch.results(job.batchId)) {
      const input = job.chapters[r.customId];
      if (!input) continue;
      if (!r.text) {
        fallback.push(input.index);
        continue;
      }
      try {
        const v = validateAndRepair(input.index, input.sentences, parseModelText(r.text), job.length);
        if (v.repairRate > MAX_REPAIR_RATE) {
          fallback.push(input.index);
          continue;
        }
        chapters.push(v.chapter);
        await this.deps.cache.set(SegmentService.cacheKey(job.contentHash, job.tier, job.length, job.level, input.index), v.chapter);
        if (r.model) {
          await this.deps.usage.add({
            userId: job.userId,
            model: r.model,
            inputTokens: r.inputTokens ?? 0,
            outputTokens: r.outputTokens ?? 0,
            costUsd: estimateCost(r.model, r.inputTokens ?? 0, r.outputTokens ?? 0, true),
            batch: true,
            at: new Date(),
          });
        }
      } catch {
        fallback.push(input.index);
      }
    }
    if (chapters.length > 0) await this.deps.quota.addBook(job.userId, this.period(), job.contentHash);
    const used = await this.deps.quota.booksUsed(job.userId, this.period());
    job.status = chapters.length > 0 ? "done" : "failed";
    job.result = {
      chapters: chapters.sort((a, b) => a.index - b.index),
      cached: 0,
      fallback,
      quota: { used: used.size, limit: quotaFor(job.tier, caller.region) },
    };
    await this.jobs.save(job);
    return job;
  }
}
