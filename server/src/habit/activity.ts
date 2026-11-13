import { randomBytes, randomUUID } from "node:crypto";

import { z } from "zod";

import type { Db } from "../db/db.js";
import {
  DAILY_MINUTES_CAP,
  displayStreak,
  emptyStreak,
  evaluateDwell,
  localDateKey,
  recordGoalMet,
  type StreakState,
} from "./engine.js";

export const ActivityBatchSchema = z.object({
  tz_offset_min: z.number().int().min(-14 * 60).max(14 * 60).default(0),
  events: z
    .array(
      z.object({
        book_id: z.string().max(80),
        card_ref: z.string().max(80),
        words: z.number().int().min(0).max(2000),
        dwell_ms: z.number().int().min(0).max(3_600_000),
        ts: z.string().datetime(),
      }),
    )
    .max(500),
});
export type ActivityBatch = z.infer<typeof ActivityBatchSchema>;

export interface UserRow {
  id: string;
  display_name: string;
  handle: string | null;
  pronouns: string;
  bio: string;
  /** An emoji (photos stay on the phone). */
  avatar: string;
  /** Up to 3 favourite genres, comma-joined. */
  genres: string;
  /** The title being read now (shown on the public profile). */
  reading: string;
  invite_code: string;
  wpm: number;
  daily_goal_cards: number;
  freezes_per_week: number;
  streak: StreakState;
  flagged: number;
  hidden: boolean;
}

const STREAK_MILESTONES = new Set([7, 30, 100, 365]);
const INVITE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"; // no 0/O/1/I/L

export function newInviteCode(): string {
  const bytes = randomBytes(8);
  return Array.from(bytes, (b) => INVITE_ALPHABET[b % INVITE_ALPHABET.length]).join("");
}

/**
 * Re-verifies reading events, keeps daily stats and streaks, and produces
 * friend activity (IMPLEMENTATION_PLAN.md Phase 7). Backed by Postgres.
 */
/** Usernames: 3–24 of a–z, 0–9, dot and underscore (stored lower case). */
export const HANDLE_PATTERN = /^[a-z0-9._]{3,24}$/;

export class HandleTaken extends Error {
  constructor(readonly handle: string) {
    super(`@${handle} is taken`);
  }
}

export class InvalidHandle extends Error {}

export interface ProfileUpdate {
  displayName?: string;
  dailyGoalCards?: number;
  freezesPerWeek?: number;
  /** "" clears the username. */
  handle?: string;
  pronouns?: string;
  bio?: string;
  avatar?: string;
  /** Up to 3; longer lists keep their first 3. */
  genres?: string[];
  reading?: string;
}

/** A reader in a followers or following list. */
export interface PersonRow {
  user_id: string;
  display_name: string;
  handle: string | null;
  avatar: string;
  /** The viewer follows this reader. */
  you_follow: boolean;
}

/** No such reader (or a hidden one). */
export class NotFollowable extends Error {}
export class CannotFollowSelf extends Error {}

export class ActivityService {
  constructor(private readonly db: Db) {}

  /** Returns the user, creating it on first sight. */
  async user(userId: string): Promise<UserRow> {
    const found = await this.db.query<UserRow>("select * from users where id = $1", [userId]);
    if (found[0]) return found[0];
    for (let attempt = 0; attempt < 5; attempt++) {
      const rows = await this.db.query<UserRow>(
        `insert into users (id, invite_code, streak) values ($1, $2, $3)
         on conflict do nothing returning *`,
        [userId, newInviteCode(), JSON.stringify(emptyStreak(1))],
      );
      if (rows[0]) return rows[0];
      const again = await this.db.query<UserRow>("select * from users where id = $1", [userId]);
      if (again[0]) return again[0]; // created concurrently
    }
    throw new Error("could not allocate an invite code");
  }

  async setProfile(userId: string, p: ProfileUpdate) {
    await this.user(userId);
    let handle: string | null | undefined;
    if (p.handle !== undefined) {
      handle = p.handle.trim().replace(/^@/, "").toLowerCase() || null;
      if (handle !== null && !HANDLE_PATTERN.test(handle)) throw new InvalidHandle("Usernames are 3–24 letters, numbers, dots or underscores.");
      if (handle !== null) {
        const taken = await this.db.query<{ id: string }>(`select id from users where lower(handle) = $1 and id <> $2`, [handle, userId]);
        if (taken.length > 0) throw new HandleTaken(handle);
      }
    }
    const clean = (v: string | undefined, max: number) => (v === undefined ? null : v.replace(/\s+$/g, "").slice(0, max));
    try {
      const rows = await this.db.query<UserRow>(
        `update users set
           display_name = coalesce($2, display_name),
           daily_goal_cards = coalesce($3, daily_goal_cards),
           freezes_per_week = coalesce($4, freezes_per_week),
           handle = case when $5::boolean then $6 else handle end,
           pronouns = coalesce($7, pronouns),
           bio = coalesce($8, bio),
           avatar = coalesce($9, avatar),
           genres = coalesce($10, genres),
           reading = coalesce($11, reading)
         where id = $1 returning *`,
        [
          userId,
          p.displayName ? p.displayName.trim().slice(0, 40) || null : null,
          p.dailyGoalCards ? Math.min(200, Math.max(1, Math.trunc(p.dailyGoalCards))) : null,
          p.freezesPerWeek !== undefined ? Math.min(7, Math.max(0, Math.trunc(p.freezesPerWeek))) : null,
          handle !== undefined,
          handle ?? null,
          clean(p.pronouns, 30),
          clean(p.bio, 150),
          p.avatar === undefined ? null : [...p.avatar.trim()].slice(0, 4).join(""),
          p.genres === undefined
            ? null
            : p.genres
                .map((g) => g.replace(/[,\s]+/g, " ").trim().slice(0, 30))
                .filter(Boolean)
                .slice(0, 3)
                .join(","),
          p.reading === undefined ? null : p.reading.replace(/\s+/g, " ").trim().slice(0, 120),
        ],
      );
      return rows[0]!;
    } catch (e) {
      // Two people claiming the same name at once: the unique index decides.
      if (handle && String((e as Error).message).includes("users_handle_lower")) throw new HandleTaken(handle);
      throw e;
    }
  }

  async ingest(userId: string, batch: ActivityBatch) {
    const u = await this.user(userId);
    let wpm = u.wpm;
    let streak = u.streak;
    let flagged = u.flagged;
    let accepted = 0;
    let verified = 0;
    let goalMetOn: string | undefined;
    const days = new Map<string, { verified_cards: number; skimmed_cards: number; minutes: number; goal_met: boolean }>();

    for (const e of batch.events) {
      const dedupe = `${e.card_ref}|${e.ts}`;
      const fresh = await this.db.query("insert into reading_events_seen (user_id, dedupe) values ($1, $2) on conflict do nothing returning 1", [
        userId,
        dedupe,
      ]);
      if (fresh.length === 0) continue;
      accepted++;
      const r = evaluateDwell(e.words, e.dwell_ms, wpm);
      wpm = r.updatedWpm;
      if (r.implausible) flagged++;
      const day = localDateKey(new Date(e.ts), batch.tz_offset_min);
      let stat = days.get(day);
      if (!stat) {
        const rows = await this.db.query<{ verified_cards: number; skimmed_cards: number; minutes: number; goal_met: boolean }>(
          "select verified_cards, skimmed_cards, minutes, goal_met from reading_days where user_id = $1 and day = $2",
          [userId, day],
        );
        stat = rows[0] ?? { verified_cards: 0, skimmed_cards: 0, minutes: 0, goal_met: false };
        days.set(day, stat);
      }
      if (r.verified) {
        stat.verified_cards++;
        stat.minutes = Math.min(DAILY_MINUTES_CAP, stat.minutes + r.minutes);
        verified++;
      } else {
        stat.skimmed_cards++;
      }
      if (!stat.goal_met && stat.verified_cards >= u.daily_goal_cards) {
        stat.goal_met = true;
        streak = recordGoalMet(streak, day, u.freezes_per_week);
        goalMetOn = day;
        await this.post(userId, "goal_met", `${u.display_name} hit today’s reading goal`);
        if (STREAK_MILESTONES.has(streak.current)) {
          await this.post(userId, "streak_milestone", `${u.display_name} reached a ${streak.current}-day streak 🔥`);
        }
      }
    }

    for (const [day, s] of days) {
      await this.db.query(
        `insert into reading_days (user_id, day, verified_cards, skimmed_cards, minutes, goal_met) values ($1,$2,$3,$4,$5,$6)
         on conflict (user_id, day) do update set verified_cards = excluded.verified_cards, skimmed_cards = excluded.skimmed_cards,
           minutes = excluded.minutes, goal_met = excluded.goal_met`,
        [userId, day, s.verified_cards, s.skimmed_cards, s.minutes, s.goal_met],
      );
    }
    await this.db.query("update users set wpm = $2, streak = $3, flagged = $4, hidden = hidden or $4 >= 20 where id = $1", [
      userId,
      wpm,
      JSON.stringify(streak),
      flagged,
    ]);
    return { accepted, verified, goalMetOn, streak: streak.current, wpm: Math.round(wpm) };
  }

  async bookFinished(userId: string, title: string) {
    const u = await this.user(userId);
    await this.post(userId, "book_finished", `${u.display_name} finished ${title.slice(0, 120)} 📚`);
  }

  async streakOf(userId: string, today: string) {
    const u = await this.user(userId);
    return { current: displayStreak(u.streak, today, u.freezes_per_week), best: u.streak.best, freezesLeft: u.streak.freezesLeft };
  }

  /** League/leaderboard score for a week: consistency first (goal days), then capped minutes. */
  async weekScores(userIds: string[], week: string): Promise<Map<string, { activeDays: number; minutes: number; score: number }>> {
    const out = new Map(userIds.map((id) => [id, { activeDays: 0, minutes: 0, score: 0 }]));
    if (userIds.length === 0) return out;
    const rows = await this.db.query<{ user_id: string; active: string | number; minutes: string | number }>(
      `select user_id, count(*) filter (where goal_met) as active, coalesce(sum(minutes), 0) as minutes
       from reading_days where user_id = any($1) and day >= $2::date and day < $2::date + 7
       group by user_id`,
      [userIds, week],
    );
    for (const r of rows) {
      const activeDays = Number(r.active);
      const minutes = Math.round(Number(r.minutes));
      out.set(r.user_id, { activeDays, minutes, score: activeDays * 1000 + minutes });
    }
    return out;
  }

  async names(userIds: string[]): Promise<Map<string, string>> {
    if (userIds.length === 0) return new Map();
    const rows = await this.db.query<{ id: string; display_name: string }>("select id, display_name from users where id = any($1)", [userIds]);
    return new Map(rows.map((r) => [r.id, r.display_name]));
  }

  /** An invite is personal: the invitee and the inviter follow each other. */
  async followByCode(userId: string, code: string): Promise<{ userId: string; name: string } | undefined> {
    await this.user(userId);
    const rows = await this.db.query<{ id: string; display_name: string }>(
      "select id, display_name from users where invite_code = $1",
      [code.trim().toUpperCase()],
    );
    const other = rows[0];
    if (!other || other.id === userId) return undefined;
    await this.db.query("insert into follows (follower, followee) values ($1, $2), ($2, $1) on conflict do nothing", [userId, other.id]);
    return { userId: other.id, name: other.display_name };
  }

  /** One-way: [userId] follows [other] (an existing reader). */
  async follow(userId: string, other: string) {
    if (userId === other) throw new CannotFollowSelf("You can't follow yourself.");
    await this.user(userId);
    const found = await this.db.query<{ id: string; hidden: boolean }>("select id, hidden from users where id = $1", [other]);
    if (!found[0] || found[0].hidden) throw new NotFollowable("No reader found.");
    await this.db.query("insert into follows (follower, followee) values ($1, $2) on conflict do nothing", [userId, other]);
  }

  /** The reader with this @username (any case, "@" optional), if any. */
  async byHandle(handle: string): Promise<UserRow | undefined> {
    const h = handle.trim().replace(/^@/, "").toLowerCase();
    if (!HANDLE_PATTERN.test(h)) return undefined;
    return (await this.db.query<UserRow>("select * from users where lower(handle) = $1", [h]))[0];
  }

  /** Follows the reader with this @username; returns who that is. */
  async followByHandle(userId: string, handle: string): Promise<PersonRow> {
    const other = await this.byHandle(handle);
    if (!other) throw new NotFollowable("No reader found.");
    await this.follow(userId, other.id);
    return { user_id: other.id, display_name: other.display_name, handle: other.handle, avatar: other.avatar, you_follow: true };
  }

  async counts(userId: string): Promise<{ followers: number; following: number }> {
    const rows = await this.db.query<{ followers: string | number; following: string | number }>(
      `select (select count(*) from follows f join users u on u.id = f.follower where f.followee = $1 and not u.hidden) as followers,
              (select count(*) from follows f join users u on u.id = f.followee where f.follower = $1 and not u.hidden) as following`,
      [userId],
    );
    return { followers: Number(rows[0]?.followers ?? 0), following: Number(rows[0]?.following ?? 0) };
  }

  /** Who follows [userId], or whom they follow, newest first (hidden readers left out). */
  async people(userId: string, viewer: string, which: "followers" | "following", limit = 200): Promise<PersonRow[]> {
    const [match, other] = which === "followers" ? ["followee", "follower"] : ["follower", "followee"];
    const rows = await this.db.query<{ id: string; display_name: string; handle: string | null; avatar: string; you_follow: boolean }>(
      `select u.id, u.display_name, u.handle, u.avatar,
              exists (select 1 from follows y where y.follower = $2 and y.followee = u.id) as you_follow
       from follows f join users u on u.id = f.${other}
       where f.${match} = $1 and not u.hidden
       order by f.created_at desc limit $3`,
      [userId, viewer, limit],
    );
    return rows.map((r) => ({ user_id: r.id, display_name: r.display_name, handle: r.handle, avatar: r.avatar, you_follow: r.you_follow }));
  }

  /** A reader by id or @username, unless hidden (hidden readers see themselves). */
  async visible(idOrHandle: string, viewer: string): Promise<UserRow | undefined> {
    const u = idOrHandle.startsWith("@")
      ? await this.byHandle(idOrHandle)
      : (await this.db.query<UserRow>("select * from users where id = $1", [idOrHandle]))[0];
    return !u || (u.hidden && u.id !== viewer) ? undefined : u;
  }

  /** What anyone can see of a reader (by id or @username). */
  async publicProfile(idOrHandle: string, viewer: string, today: string) {
    const u = await this.visible(idOrHandle, viewer);
    if (!u) return undefined;
    const [counts, rel] = await Promise.all([
      this.counts(u.id),
      this.db.query<{ you_follow: boolean; follows_you: boolean }>(
        `select exists (select 1 from follows where follower = $1 and followee = $2) as you_follow,
                exists (select 1 from follows where follower = $2 and followee = $1) as follows_you`,
        [viewer, u.id],
      ),
    ]);
    return {
      user_id: u.id,
      display_name: u.display_name,
      handle: u.handle,
      pronouns: u.pronouns,
      bio: u.bio,
      avatar: u.avatar,
      genres: u.genres ? u.genres.split(",").filter(Boolean) : [],
      reading: u.reading,
      ...counts,
      streak: { current: displayStreak(u.streak, today, u.freezes_per_week), best: u.streak.best },
      you_follow: rel[0]?.you_follow ?? false,
      follows_you: rel[0]?.follows_you ?? false,
      me: u.id === viewer,
    };
  }

  async unfollow(userId: string, other: string) {
    await this.db.query("delete from follows where follower = $1 and followee = $2", [userId, other]);
  }

  async following(userId: string): Promise<string[]> {
    return (await this.db.query<{ followee: string }>("select followee from follows where follower = $1", [userId])).map((r) => r.followee);
  }

  async friendsLeaderboard(userId: string, week: string) {
    await this.user(userId);
    const ids = [userId, ...(await this.following(userId))];
    const [scores, names] = await Promise.all([this.weekScores(ids, week), this.names(ids)]);
    return ids
      .map((id) => ({ userId: id, name: names.get(id) ?? "Reader", me: id === userId, ...scores.get(id)! }))
      .sort((a, b) => b.score - a.score);
  }

  private async post(userId: string, type: string, text: string) {
    await this.db.query("insert into feed_items (id, user_id, type, text) values ($1, $2, $3, $4)", [randomUUID(), userId, type, text]);
  }
}
