import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";

import { z } from "zod";

import type { Db } from "./db/db.js";

/**
 * Abuse protection (Production plan A4): rate limits, a text filter for
 * what other readers see (names, usernames, bios, comments), blocking, and
 * reports with automatic safeguards until a person reviews them.
 */

// ------------------------------------------------------------------ rate limits

export class RateLimited extends Error {
  constructor(readonly retryAfterSec: number) {
    super("Too many requests");
  }
}

export interface Limit {
  limit: number;
  windowMs: number;
}

const MIN = 60_000;
const HOUR = 60 * MIN;
const DAY = 24 * HOUR;

/** Per reader, per action. Generous for people, tight for scripts. */
export const LIMITS = {
  comment: [{ limit: 10, windowMs: MIN }, { limit: 200, windowMs: DAY }],
  follow: [{ limit: 30, windowMs: MIN }, { limit: 500, windowMs: DAY }],
  kudos: [{ limit: 60, windowMs: MIN }],
  session: [{ limit: 120, windowMs: HOUR }],
  profile: [{ limit: 30, windowMs: HOUR }],
  share: [{ limit: 60, windowMs: HOUR }],
  report: [{ limit: 30, windowMs: DAY }],
  block: [{ limit: 60, windowMs: HOUR }],
  /** Crash reports from the app. */
  error: [{ limit: 30, windowMs: HOUR }],
  /** Every /v1 request, per IP address. */
  ip: [{ limit: 600, windowMs: MIN }],
} satisfies Record<string, Limit[]>;
export type LimitName = keyof typeof LIMITS;

/**
 * Fixed windows kept in memory: per server instance, which is enough to stop
 * floods; a shared store (Redis) is the next step when running many
 * instances behind a load balancer.
 */
export class RateLimiter {
  private readonly hits = new Map<string, { start: number; count: number }>();
  constructor(private readonly clock: () => number = Date.now) {}

  /** Counts one hit for [key] under [name]; throws [RateLimited] when over. */
  hit(name: LimitName, key: string) {
    const now = this.clock();
    for (const [i, rule] of LIMITS[name].entries()) {
      const k = `${name}:${i}:${key}`;
      const w = this.hits.get(k);
      if (!w || now - w.start >= rule.windowMs) {
        this.hits.set(k, { start: now, count: 1 });
        continue;
      }
      if (w.count >= rule.limit) throw new RateLimited(Math.ceil((w.start + rule.windowMs - now) / 1000));
      w.count++;
    }
    if (this.hits.size > 50_000) this.sweep(now);
  }

  private sweep(now: number) {
    for (const [k, w] of this.hits) if (now - w.start > DAY) this.hits.delete(k);
  }
}

// ------------------------------------------------------------------ text filter

export class NotAllowed extends Error {}

/** Usernames that could pass for the app or its staff. */
const RESERVED = /^(cloro.*|bookreel.*|admin.*|administrator|support|help|helpdesk|official|moderator|mod|mods|staff|team|security|system|root|null|undefined|everyone|anonymous|me)$/;

/** Links are how spam spreads: not in names, bios or comments. */
const LINK = /(https?:\/\/|www\.|\b[a-z0-9-]{2,}\.(com|net|org|io|xyz|ru|cn|info|biz|top|link|click|site|online|shop|live|app|me|ly|gg|co|in)\b)/i;

/** Common spam phrases; offensive words come from MODERATION_WORDS_FILE. */
const SPAM = ["free money", "crypto giveaway", "investment opportunity", "whatsapp me", "telegram me", "dm me for", "click here", "earn from home", "promo code"];

const LEET: Record<string, string> = { "0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "@": "a", $: "s", "!": "i" };

/** Lower case, look-alike characters folded, long repeats shortened. */
export function normalizeText(s: string): string {
  return s
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/[013457@$!]/g, (c) => LEET[c] ?? c)
    .replace(/(.)\1{2,}/g, "$1$1");
}

export class TextFilter {
  private readonly words: string[];

  /** [words]: one word or phrase per entry (e.g. from MODERATION_WORDS_FILE). */
  constructor(words: string[] = []) {
    this.words = [...SPAM, ...words].map((w) => normalizeText(w.trim())).filter(Boolean);
  }

  static fromEnv(env: NodeJS.ProcessEnv = process.env): TextFilter {
    const file = env.MODERATION_WORDS_FILE;
    if (!file) return new TextFilter();
    return new TextFilter(readFileSync(file, "utf8").split(/\r?\n/).filter((l) => l && !l.startsWith("#")));
  }

  /** Throws [NotAllowed] with a message the reader can act on. */
  check(text: string, kind: "comment" | "bio" | "name" | "handle") {
    if (!text) return;
    if (kind === "handle" && RESERVED.test(text.toLowerCase())) throw new NotAllowed("That username is reserved. Try another.");
    if (kind !== "handle" && LINK.test(text)) throw new NotAllowed("Links aren't allowed here.");
    const t = ` ${normalizeText(text).replace(/[^a-z0-9]+/g, " ")} `;
    const squashed = normalizeText(text).replace(/[^a-z0-9]/g, "");
    for (const w of this.words) {
      const spaced = ` ${w.replace(/[^a-z0-9]+/g, " ")} `;
      // Whole words, or the word hidden by squashing (u.s.e.r → user).
      if (t.includes(spaced) || (w.length >= 5 && squashed.includes(w.replace(/[^a-z0-9]/g, "")))) {
        throw new NotAllowed("That can't be posted. Please keep Cloro kind.");
      }
    }
  }
}

// ------------------------------------------------------------------ blocks and reports

export const REPORT_REASONS = ["spam", "harassment", "hate", "sexual", "self_harm", "impersonation", "other"] as const;

export const ReportSchema = z
  .object({
    type: z.enum(["user", "activity", "comment"]),
    id: z.string().min(1).max(200),
    reason: z.enum(REPORT_REASONS),
    note: z.string().trim().max(300).default(""),
  })
  .strict();
export type ReportInput = z.infer<typeof ReportSchema>;

/** A comment held back after this many readers report it. */
export const HIDE_COMMENT_AFTER = 2;
/** A reader hidden (until reviewed) after this many readers report them in 30 days. */
export const HIDE_USER_AFTER = 3;

/** SQL: neither [a] nor [b] has blocked the other. */
export const notBlocked = (a: string, b: string) =>
  `not exists (select 1 from blocks bl where (bl.blocker = ${a} and bl.blocked = ${b}) or (bl.blocker = ${b} and bl.blocked = ${a}))`;

export class ModerationService {
  constructor(private readonly db: Db) {}

  async isBlocked(a: string, b: string): Promise<boolean> {
    const rows = await this.db.query(`select 1 from blocks where (blocker = $1 and blocked = $2) or (blocker = $2 and blocked = $1)`, [a, b]);
    return rows.length > 0;
  }

  /** You stop following each other, and neither can find, follow or comment on the other. */
  async block(userId: string, other: string) {
    if (userId === other) throw new NotAllowed("You can't block yourself.");
    const found = await this.db.query("select 1 from users where id = $1", [other]);
    if (!found.length) return false;
    await this.db.query(
      `with b as (insert into blocks (blocker, blocked) values ($1, $2) on conflict do nothing)
       delete from follows where (follower = $1 and followee = $2) or (follower = $2 and followee = $1)`,
      [userId, other],
    );
    return true;
  }

  async unblock(userId: string, other: string) {
    await this.db.query("delete from blocks where blocker = $1 and blocked = $2", [userId, other]);
  }

  async blocked(userId: string) {
    return this.db.query<{ user_id: string; display_name: string; handle: string | null; avatar: string }>(
      `select u.id as user_id, u.display_name, u.handle, u.avatar
       from blocks b join users u on u.id = b.blocked where b.blocker = $1 order by b.created_at desc`,
      [userId],
    );
  }

  /** The reader behind a reported thing (undefined if it doesn't exist). */
  private async targetUser(reporter: string, r: ReportInput): Promise<string | undefined> {
    if (r.type === "user") {
      const u = await this.db.query<{ id: string }>("select id from users where id = $1", [r.id]);
      return u[0]?.id;
    }
    const sql =
      r.type === "activity"
        ? "select f.user_id as author from feed_items f where f.id = $1"
        : "select c.user_id as author from comments c where c.id = $1";
    const rows = await this.db.query<{ author: string }>(sql, [r.id]);
    return rows[0]?.author;
  }

  /**
   * Records a report (once per reader per thing). A comment is held back
   * after [HIDE_COMMENT_AFTER] readers report it; a reader is hidden after
   * [HIDE_USER_AFTER] readers report them within 30 days, until reviewed.
   */
  async report(reporter: string, r: ReportInput): Promise<boolean> {
    const target = await this.targetUser(reporter, r);
    if (!target || target === reporter) return false;
    await this.db.query(
      `insert into reports (id, reporter, target_type, target_id, target_user, reason, note) values ($1, $2, $3, $4, $5, $6, $7)
       on conflict (reporter, target_type, target_id) do nothing`,
      [randomUUID(), reporter, r.type, r.id, target, r.reason, r.note],
    );
    if (r.type === "comment") {
      await this.db.query(
        `update comments set hidden = true where id = $1 and
           (select count(distinct reporter) from reports where target_type = 'comment' and target_id = $1) >= $2`,
        [r.id, HIDE_COMMENT_AFTER],
      );
    }
    await this.db.query(
      `update users set hidden = true where id = $1 and
         (select count(distinct reporter) from reports where target_user = $1 and created_at > now() - interval '30 days' and status = 'open') >= $2`,
      [target, HIDE_USER_AFTER],
    );
    return true;
  }

  /** Open reports with what was reported, for review. */
  async openReports(limit = 100) {
    return this.db.query(
      `select r.id, r.target_type, r.target_id, r.target_user, r.reason, r.note, r.created_at, r.reporter,
              u.display_name as target_name, u.handle as target_handle, u.bio as target_bio, u.hidden as target_hidden,
              (select c.text from comments c where r.target_type = 'comment' and c.id = r.target_id) as comment_text,
              (select f.text from feed_items f where r.target_type = 'activity' and f.id = r.target_id) as activity_text
       from reports r left join users u on u.id = r.target_user
       where r.status = 'open' order by r.created_at asc limit $1`,
      [limit],
    );
  }

  /** dismiss: keep everything; remove: delete the comment or activity; hide_user / restore_user. */
  async resolve(reportId: string, action: "dismiss" | "remove" | "hide_user" | "restore_user"): Promise<boolean> {
    const rows = await this.db.query<{ target_type: string; target_id: string; target_user: string }>(
      "select target_type, target_id, target_user from reports where id = $1",
      [reportId],
    );
    const r = rows[0];
    if (!r) return false;
    if (action === "remove" && r.target_type === "comment") await this.db.query("delete from comments where id = $1", [r.target_id]);
    if (action === "remove" && r.target_type === "activity") {
      await this.db.query(
        `with k as (delete from kudos where activity_id = $1) delete from feed_items where id = $1`,
        [r.target_id],
      );
    }
    if (action === "hide_user") await this.db.query("update users set hidden = true where id = $1", [r.target_user]);
    if (action === "restore_user") await this.db.query("update users set hidden = false where id = $1", [r.target_user]);
    if (action === "dismiss" && r.target_type === "comment") await this.db.query("update comments set hidden = false where id = $1", [r.target_id]);
    // Every open report about the same thing is settled together.
    await this.db.query(
      `update reports set status = $1 where status = 'open' and target_type = $2 and target_id = $3`,
      [action === "dismiss" ? "dismissed" : "actioned", r.target_type, r.target_id],
    );
    return true;
  }
}
