import type { Db } from "../db/db.js";
import type { OutChapter } from "../segmentation/schema.js";
import type { BatchJob, JobStore } from "../segmentation/service.js";
import type { QuotaStore, SegmentCache, UsageLog, UsageRecord } from "./memory.js";

export class SqlSegmentCache implements SegmentCache {
  constructor(private readonly db: Db) {}
  async get(key: string) {
    const rows = await this.db.query<{ value: OutChapter }>("select value from segment_cache where key = $1", [key]);
    return rows[0]?.value;
  }
  async set(key: string, value: OutChapter) {
    await this.db.query(
      "insert into segment_cache (key, value) values ($1, $2) on conflict (key) do update set value = excluded.value",
      [key, JSON.stringify(value)],
    );
  }
}

export class SqlQuotaStore implements QuotaStore {
  constructor(private readonly db: Db) {}
  async booksUsed(userId: string, period: string) {
    const rows = await this.db.query<{ content_hash: string }>(
      "select content_hash from quota_books where user_id = $1 and period = $2",
      [userId, period],
    );
    return new Set(rows.map((r) => r.content_hash));
  }
  async addBook(userId: string, period: string, contentHash: string) {
    await this.db.query("insert into quota_books values ($1, $2, $3) on conflict do nothing", [userId, period, contentHash]);
  }
}

export class SqlUsageLog implements UsageLog {
  constructor(private readonly db: Db) {}
  async add(r: UsageRecord) {
    await this.db.query(
      "insert into ai_usage (user_id, model, input_tokens, output_tokens, cost_usd, batch, at) values ($1,$2,$3,$4,$5,$6,$7)",
      [r.userId, r.model, r.inputTokens, r.outputTokens, r.costUsd, r.batch, r.at.toISOString()],
    );
  }
}

interface JobRow {
  id: string;
  batch_id: string;
  user_id: string;
  content_hash: string;
  tier: BatchJob["tier"];
  card_length: BatchJob["length"];
  reading_level: BatchJob["level"];
  chapters: BatchJob["chapters"];
  status: BatchJob["status"];
  result: BatchJob["result"] | null;
  created_at: string | Date;
}

export class SqlJobStore implements JobStore {
  constructor(private readonly db: Db) {}
  async get(id: string): Promise<BatchJob | undefined> {
    const r = (await this.db.query<JobRow>("select * from batch_jobs where id = $1", [id]))[0];
    if (!r) return undefined;
    return {
      id: r.id,
      batchId: r.batch_id,
      userId: r.user_id,
      contentHash: r.content_hash,
      tier: r.tier,
      length: r.card_length,
      level: r.reading_level,
      chapters: r.chapters,
      status: r.status,
      result: r.result ?? undefined,
      createdAt: new Date(r.created_at),
    };
  }
  async save(job: BatchJob) {
    await this.db.query(
      `insert into batch_jobs (id, batch_id, user_id, content_hash, tier, card_length, reading_level, chapters, status, result)
       values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
       on conflict (id) do update set status = excluded.status, result = excluded.result`,
      [
        job.id, job.batchId, job.userId, job.contentHash, job.tier, job.length, job.level,
        JSON.stringify(job.chapters), job.status, job.result ? JSON.stringify(job.result) : null,
      ],
    );
  }
}
