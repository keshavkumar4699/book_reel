import { z } from "zod";

import type { Db } from "../db/db.js";

export const SYNC_KINDS = ["highlight", "saved", "word", "reflection", "position", "like"] as const;

export const SyncPushSchema = z.object({
  items: z
    .array(
      z.object({
        kind: z.enum(SYNC_KINDS),
        id: z.string().min(1).max(200),
        updated_at: z.number().int().nonnegative(),
        deleted: z.boolean().default(false),
        data: z.unknown().optional(),
      }),
    )
    .max(1000),
});
export type SyncPush = z.infer<typeof SyncPushSchema>;

/**
 * Notebook and reading-position sync. Last write wins per item, using the
 * client's `updated_at` (ms); deletions are kept as tombstones so other
 * devices learn about them. Clients pull with a server sequence cursor.
 */
export class SyncService {
  constructor(private readonly db: Db) {}

  async push(userId: string, push: SyncPush): Promise<{ applied: number; cursor: number }> {
    let applied = 0;
    for (const item of push.items) {
      const data = item.deleted ? null : JSON.stringify(item.data ?? null);
      if (data && data.length > 20_000) continue; // a single notebook item is never this large
      const rows = await this.db.query(
        `insert into sync_items (user_id, kind, item_id, data, updated_at, deleted) values ($1, $2, $3, $4, $5, $6)
         on conflict (user_id, kind, item_id) do update
           set data = excluded.data, updated_at = excluded.updated_at, deleted = excluded.deleted, seq = nextval('sync_seq')
           where sync_items.updated_at < excluded.updated_at
         returning 1`,
        [userId, item.kind, item.id, data, item.updated_at, item.deleted],
      );
      applied += rows.length;
    }
    return { applied, cursor: await this.cursor(userId) };
  }

  async pull(userId: string, since: number, limit = 500) {
    const rows = await this.db.query<{ kind: string; item_id: string; data: unknown; updated_at: string | number; deleted: boolean; seq: string | number }>(
      "select kind, item_id, data, updated_at, deleted, seq from sync_items where user_id = $1 and seq > $2 order by seq limit $3",
      [userId, since, limit],
    );
    const items = rows.map((r) => ({
      kind: r.kind,
      id: r.item_id,
      data: r.deleted ? undefined : r.data,
      updated_at: Number(r.updated_at),
      deleted: r.deleted,
    }));
    const last = rows.length ? Number(rows[rows.length - 1]!.seq) : since;
    return { items, cursor: last, more: rows.length === limit };
  }

  private async cursor(userId: string): Promise<number> {
    const rows = await this.db.query<{ m: string | number | null }>("select max(seq) as m from sync_items where user_id = $1", [userId]);
    return Number(rows[0]?.m ?? 0);
  }
}
