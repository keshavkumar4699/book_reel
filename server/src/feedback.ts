import { randomUUID } from "node:crypto";

import { z } from "zod";

import type { Db } from "./db/db.js";

/** What a reader sends from Settings → Send feedback (Production plan B8). */
export const FeedbackSchema = z
  .object({
    kind: z.enum(["idea", "problem", "other"]).default("other"),
    message: z.string().trim().min(1).max(2000),
    /** An email to reply to, if the reader wants a reply. */
    contact: z.string().trim().max(200).default(""),
    version: z.string().max(40).default(""),
    platform: z.string().max(40).default(""),
    locale: z.string().max(20).default(""),
    /** e.g. "Android 15 · Pixel 8", only when the reader allows it. */
    device: z.string().max(120).default(""),
  })
  .strict();

export type Feedback = z.infer<typeof FeedbackSchema>;

/** Feedback from readers: kept until handled, deleted with the account. */
export class FeedbackService {
  constructor(private readonly db: Db) {}

  async add(userId: string, f: Feedback): Promise<string> {
    const id = randomUUID();
    await this.db.query(
      `insert into feedback (id, user_id, kind, message, contact, app_version, platform, locale, device)
       values ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
      [id, userId, f.kind, f.message, f.contact, f.version, f.platform, f.locale, f.device],
    );
    return id;
  }

  /** Unhandled feedback, newest first. */
  async open(limit = 200) {
    return this.db.query(
      `select id, kind, message, contact, app_version, platform, locale, device, created_at
       from feedback where status = 'open' order by created_at desc limit $1`,
      [limit],
    );
  }

  async markDone(id: string): Promise<boolean> {
    const rows = await this.db.query(`update feedback set status = 'done' where id = $1 returning id`, [id]);
    return rows.length > 0;
  }
}
