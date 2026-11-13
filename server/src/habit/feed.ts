import { randomUUID } from "node:crypto";

import { z } from "zod";

import type { Db } from "../db/db.js";
import { notBlocked } from "../moderation.js";
import { MOODS } from "../mood/suggest.js";

/**
 * The Today feed (Cloro plan §10), Strava-style: reading sessions and
 * milestones from you and the readers you follow, with kudos and comments.
 *
 * A session is posted by the app as it grows (every few cards); its own
 * session id (`client_id`) makes each upload update the same card.
 */

export const SessionSchema = z
  .object({
    client_id: z.string().regex(/^[A-Za-z0-9_-]{8,64}$/),
    started_at: z.string().datetime(),
    minutes: z.number().min(0).max(600),
    cards: z.number().int().min(0).max(2000),
    book: z.object({ title: z.string().trim().min(1).max(200), author: z.string().trim().max(120).default("") }).strict(),
    /** How far into the book, 0–1. */
    progress: z.number().min(0).max(1).default(0),
    mood: z.enum(MOODS).optional(),
    /** A line saved during the session (public-domain books only, the app decides). */
    quote: z.string().trim().max(280).optional(),
  })
  .strict();
export type SessionPost = z.infer<typeof SessionSchema>;

export const CommentSchema = z.object({ text: z.string().trim().min(1).max(300) }).strict();

export class NotVisible extends Error {}

export interface FeedItem {
  id: string;
  userId: string;
  type: string;
  text: string;
  at: string;
  data: Record<string, unknown>;
  author: { name: string; handle: string | null; avatar: string };
  kudos: number;
  gaveKudos: boolean;
  comments: number;
  mine: boolean;
}

export class FeedService {
  constructor(private readonly db: Db) {}

  /** Creates or updates the session's card; nothing for an empty session. */
  async postSession(userId: string, s: SessionPost): Promise<{ id: string } | null> {
    if (s.cards === 0 && s.minutes < 1) return null;
    const name = (await this.db.query<{ display_name: string }>("select display_name from users where id = $1", [userId]))[0]?.display_name ?? "Reader";
    const data = {
      book: s.book,
      minutes: Math.round(s.minutes * 10) / 10,
      cards: s.cards,
      progress: Math.round(s.progress * 1000) / 1000,
      ...(s.mood ? { mood: s.mood } : {}),
      ...(s.quote ? { quote: s.quote } : {}),
    };
    const rows = await this.db.query<{ id: string }>(
      `insert into feed_items (id, user_id, type, text, at, data, client_id) values ($1, $2, 'session', $3, $4, $5, $6)
       on conflict (user_id, client_id) where client_id is not null
       do update set data = excluded.data, text = excluded.text
       returning id`,
      [randomUUID(), userId, `${name} read ${s.book.title}`, s.started_at, JSON.stringify(data), s.client_id],
    );
    return { id: rows[0]!.id };
  }

  /**
   * Posts (or raises) a "best week" milestone when this week's reading beats
   * every earlier week (after at least one earlier week of 30+ minutes).
   */
  async checkBestWeek(userId: string, name: string, today: string) {
    const rows = await this.db.query<{ wk: string | Date; minutes: string | number }>(
      `select date_trunc('week', day)::date as wk, sum(minutes) as minutes
       from reading_days where user_id = $1 group by 1`,
      [userId],
    );
    const key = (v: string | Date) => (v instanceof Date ? v.toISOString() : String(v)).slice(0, 10);
    const thisWeek = key((await this.db.query<{ wk: string | Date }>(`select date_trunc('week', $1::date)::date as wk`, [today]))[0]!.wk);
    let now = 0;
    let best = 0;
    for (const r of rows) {
      const m = Number(r.minutes);
      if (key(r.wk) === thisWeek) now = m;
      else if (key(r.wk) < thisWeek) best = Math.max(best, m);
    }
    if (best < 30 || now <= best) return;
    const minutes = Math.round(now);
    await this.db.query(
      `insert into feed_items (id, user_id, type, text, data, client_id) values ($1, $2, 'best_week', $3, $4, $5)
       on conflict (user_id, client_id) where client_id is not null do update set data = excluded.data, text = excluded.text`,
      [randomUUID(), userId, `${name} had their best reading week: ${minutes} min 🏆`, JSON.stringify({ minutes, week: thisWeek }), `best_week:${thisWeek}`],
    );
  }

  /** You see your own activities and those of readers you follow (not hidden ones). */
  async canSee(userId: string, activityId: string): Promise<{ authorId: string } | undefined> {
    const rows = await this.db.query<{ user_id: string }>(
      `select f.user_id from feed_items f join users u on u.id = f.user_id
       where f.id = $2 and (f.user_id = $1 or (not u.hidden and exists (select 1 from follows where follower = $1 and followee = f.user_id)
         and ${notBlocked("$1", "f.user_id")}))`,
      [userId, activityId],
    );
    return rows[0] ? { authorId: rows[0].user_id } : undefined;
  }

  /** Newest first; [before] (an ISO time) pages back. Goal-met lines are left to the streak. */
  async feedFor(userId: string, opts: { before?: string; limit?: number } = {}): Promise<FeedItem[]> {
    const limit = Math.min(50, Math.max(1, opts.limit ?? 20));
    const rows = await this.db.query<{
      id: string;
      user_id: string;
      type: string;
      text: string;
      at: string | Date;
      data: Record<string, unknown> | string;
      display_name: string;
      handle: string | null;
      avatar: string;
      kudos: string | number;
      gave: boolean;
      comments: string | number;
    }>(
      `select f.id, f.user_id, f.type, f.text, f.at, f.data, u.display_name, u.handle, u.avatar,
              (select count(*) from kudos k where k.activity_id = f.id) as kudos,
              exists (select 1 from kudos k where k.activity_id = f.id and k.user_id = $1) as gave,
              (select count(*) from comments c where c.activity_id = f.id and not c.hidden) as comments
       from feed_items f join users u on u.id = f.user_id
       where (f.user_id = $1 or (not u.hidden and f.user_id in (select followee from follows where follower = $1) and ${notBlocked("$1", "f.user_id")}))
         and f.type <> 'goal_met'
         and ($3::timestamptz is null or f.at < $3::timestamptz)
       order by f.at desc, f.id desc limit $2`,
      [userId, limit, opts.before ?? null],
    );
    return rows.map((r) => ({
      id: r.id,
      userId: r.user_id,
      type: r.type,
      text: r.text,
      at: new Date(r.at).toISOString(),
      data: typeof r.data === "string" ? (JSON.parse(r.data) as Record<string, unknown>) : r.data ?? {},
      author: { name: r.display_name, handle: r.handle, avatar: r.avatar },
      kudos: Number(r.kudos),
      gaveKudos: r.gave,
      comments: Number(r.comments),
      mine: r.user_id === userId,
    }));
  }

  /** Kudos only (no dislikes); false for activities you can't see, or your own. */
  async kudos(userId: string, activityId: string): Promise<boolean> {
    const seen = await this.canSee(userId, activityId);
    if (!seen || seen.authorId === userId) return false;
    await this.db.query("insert into kudos (activity_id, user_id) values ($1, $2) on conflict do nothing", [activityId, userId]);
    return true;
  }

  async comments(userId: string, activityId: string) {
    const seen = await this.canSee(userId, activityId);
    if (!seen) throw new NotVisible("Not found");
    const rows = await this.db.query<{ id: string; user_id: string; display_name: string; handle: string | null; avatar: string; text: string; at: string | Date }>(
      `select c.id, c.user_id, u.display_name, u.handle, u.avatar, c.text, c.at
       from comments c join users u on u.id = c.user_id
       where c.activity_id = $1 and (c.user_id = $2 or (not u.hidden and not c.hidden and ${notBlocked("$2", "c.user_id")}))
       order by c.at asc, c.id asc limit 200`,
      [activityId, userId],
    );
    return rows.map((r) => ({
      id: r.id,
      user_id: r.user_id,
      name: r.display_name,
      handle: r.handle,
      avatar: r.avatar,
      text: r.text,
      at: new Date(r.at).toISOString(),
      mine: r.user_id === userId,
      // The author of the activity may remove comments on it.
      can_delete: r.user_id === userId || seen.authorId === userId,
    }));
  }

  async addComment(userId: string, activityId: string, text: string) {
    if (!(await this.canSee(userId, activityId))) throw new NotVisible("Not found");
    const id = randomUUID();
    const clean = text.replace(/\s+/g, " ").trim().slice(0, 300);
    const rows = await this.db.query<{ at: string | Date }>(
      "insert into comments (id, activity_id, user_id, text) values ($1, $2, $3, $4) returning at",
      [id, activityId, userId, clean],
    );
    return { id, text: clean, at: new Date(rows[0]!.at).toISOString() };
  }

  /** Your own comment, or any comment on your activity. */
  async deleteComment(userId: string, commentId: string): Promise<boolean> {
    const rows = await this.db.query<{ id: string }>(
      `delete from comments c using feed_items f
       where c.id = $1 and f.id = c.activity_id and (c.user_id = $2 or f.user_id = $2)
       returning c.id`,
      [commentId, userId],
    );
    return rows.length > 0;
  }
}
