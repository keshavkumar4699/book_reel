import type { Db } from "./db/db.js";

/**
 * A reader's own data (Production plan A3): download all of it, or delete
 * the account. Google Play requires in-app account deletion and a web page
 * explaining how to ask for it.
 */
export class AccountService {
  constructor(private readonly db: Db) {}

  /**
   * Erases the account and everything tied to it, in one statement (so it
   * is all or nothing): profile, sign-in links, reading days and events,
   * follows both ways, activities with their kudos and comments, comments
   * and kudos given, league places, synced notebook and positions, share
   * links, usage counters and AI jobs. AI cost records stay for accounting
   * without the user's id; purchases stay with Google, unlinked from it.
   */
  async delete(userId: string): Promise<boolean> {
    const rows = await this.db.query<{ id: string }>(
      `with
         mine as (select id from feed_items where user_id = $1),
         k as (delete from kudos where user_id = $1 or activity_id in (select id from mine)),
         c as (delete from comments where user_id = $1 or activity_id in (select id from mine)),
         f as (delete from feed_items where user_id = $1),
         fo as (delete from follows where follower = $1 or followee = $1),
         lm as (delete from league_members where user_id = $1 returning group_id),
         lg as (update league_groups set members = greatest(0, members - 1) where id in (select group_id from lm)),
         ld as (delete from league_divisions where user_id = $1),
         rd as (delete from reading_days where user_id = $1),
         rs as (delete from reading_events_seen where user_id = $1),
         si as (delete from sync_items where user_id = $1),
         sh as (delete from shares where user_id = $1),
         tu as (delete from tts_usage where user_id = $1),
         mu as (delete from mood_usage where user_id = $1),
         qb as (delete from quota_books where user_id = $1),
         bj as (delete from batch_jobs where user_id = $1),
         au as (update ai_usage set user_id = 'deleted' where user_id = $1),
         en as (update entitlements set user_id = null where user_id = $1),
         bl as (delete from blocks where blocker = $1 or blocked = $1),
         rp as (delete from reports where reporter = $1 or target_user = $1),
         al as (delete from aliases where user_id = $1)
       delete from users where id = $1 returning id`,
      [userId],
    );
    return rows.length > 0;
  }

  /** Everything the server keeps about the reader, as one JSON document. */
  async export(userId: string) {
    const q = <T>(sql: string) => this.db.query<T>(sql, [userId]);
    const [user] = await q<Record<string, unknown>>(
      `select id, display_name, handle, pronouns, bio, avatar, genres, reading, invite_code, daily_goal_cards,
              freezes_per_week, streak, created_at
       from users where id = $1`,
    );
    if (!user) return undefined;
    const [readingDays, following, followers, activities, comments, kudos, notebook, shares, subscriptions, tts, mood, aiBooks] =
      await Promise.all([
        q("select day, verified_cards, skimmed_cards, minutes, goal_met from reading_days where user_id = $1 order by day"),
        q("select u.id, u.display_name, u.handle, f.created_at from follows f join users u on u.id = f.followee where f.follower = $1 order by f.created_at"),
        q("select u.id, u.display_name, u.handle, f.created_at from follows f join users u on u.id = f.follower where f.followee = $1 order by f.created_at"),
        q("select id, type, text, at, data from feed_items where user_id = $1 order by at"),
        q("select id, activity_id, text, at from comments where user_id = $1 order by at"),
        q("select activity_id from kudos where user_id = $1"),
        q("select kind, item_id, data, updated_at from sync_items where user_id = $1 and not deleted order by kind, item_id"),
        q("select id, type, payload, open_count, created_at from shares where user_id = $1 order by created_at"),
        q("select product_id, tier, state, expires_at from entitlements where user_id = $1"),
        q("select day, chars from tts_usage where user_id = $1 order by day"),
        q("select day, calls from mood_usage where user_id = $1 order by day"),
        q("select period, count(*) as books from quota_books where user_id = $1 group by period order by period"),
      ]);
    return {
      exported_at: new Date().toISOString(),
      user: { ...user, genres: String(user.genres ?? "").split(",").filter(Boolean) },
      reading_days: readingDays,
      following,
      followers,
      activities,
      comments,
      kudos_given: kudos,
      notebook,
      shares,
      subscriptions,
      usage: { read_aloud_characters: tts, mood_suggestions: mood, ai_books: aiBooks },
    };
  }
}
