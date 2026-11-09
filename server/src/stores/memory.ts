import type { OutChapter } from "../segmentation/schema.js";

/**
 * Storage interfaces with in-memory implementations. Production swaps these
 * for Postgres/Redis/Cloud Storage (DESIGN.md §3.5 and §7) without touching
 * the services.
 */
export interface SegmentCache {
  get(key: string): Promise<OutChapter | undefined>;
  set(key: string, value: OutChapter): Promise<void>;
}

export interface QuotaStore {
  /** Content hashes that already counted toward [userId]'s quota in [period] (yyyy-mm). */
  booksUsed(userId: string, period: string): Promise<Set<string>>;
  addBook(userId: string, period: string, contentHash: string): Promise<void>;
}

export interface UsageRecord {
  userId: string;
  model: string;
  inputTokens: number;
  outputTokens: number;
  costUsd: number;
  batch: boolean;
  at: Date;
}

export interface UsageLog {
  add(record: UsageRecord): Promise<void>;
}

export class MemorySegmentCache implements SegmentCache {
  private readonly map = new Map<string, OutChapter>();
  async get(key: string) {
    return this.map.get(key);
  }
  async set(key: string, value: OutChapter) {
    this.map.set(key, value);
  }
  get size() {
    return this.map.size;
  }
}

export class MemoryQuotaStore implements QuotaStore {
  private readonly map = new Map<string, Set<string>>();
  async booksUsed(userId: string, period: string) {
    return new Set(this.map.get(`${userId}|${period}`) ?? []);
  }
  async addBook(userId: string, period: string, contentHash: string) {
    const k = `${userId}|${period}`;
    const set = this.map.get(k) ?? new Set<string>();
    set.add(contentHash);
    this.map.set(k, set);
  }
}

export class MemoryUsageLog implements UsageLog {
  readonly records: UsageRecord[] = [];
  async add(record: UsageRecord) {
    this.records.push(record);
  }
}
