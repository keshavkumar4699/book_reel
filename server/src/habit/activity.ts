import { randomUUID } from "node:crypto";

import { z } from "zod";

import {
  DAILY_MINUTES_CAP,
  DEFAULT_WPM,
  displayStreak,
  emptyStreak,
  evaluateDwell,
  localDateKey,
  recordGoalMet,
  weekKey,
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

export interface DayStat {
  verifiedCards: number;
  skimmedCards: number;
  minutes: number;
  goalMet: boolean;
}

export interface UserHabit {
  userId: string;
  displayName: string;
  wpm: number;
  dailyGoalCards: number;
  freezesPerWeek: number;
  days: Map<string, DayStat>;
  streak: StreakState;
  seen: Set<string>;
  flagged: number;
  following: Set<string>;
  /** Hidden from public boards until reviewed (anomaly detection). */
  hidden: boolean;
}

export interface FeedItem {
  id: string;
  userId: string;
  type: "goal_met" | "book_finished" | "streak_milestone";
  text: string;
  at: Date;
  kudos: Set<string>;
}

const STREAK_MILESTONES = new Set([7, 30, 100, 365]);

/**
 * Re-verifies reading events, keeps daily stats and streaks, and produces
 * friend activity (IMPLEMENTATION_PLAN.md Phase 7). In-memory; production
 * persists to Postgres with the schema in DESIGN.md §7.
 */
export class ActivityService {
  private readonly users = new Map<string, UserHabit>();
  private readonly feed: FeedItem[] = [];

  user(userId: string): UserHabit {
    let u = this.users.get(userId);
    if (!u) {
      u = {
        userId,
        displayName: "Reader",
        wpm: DEFAULT_WPM,
        dailyGoalCards: 10,
        freezesPerWeek: 1,
        days: new Map(),
        streak: emptyStreak(1),
        seen: new Set(),
        flagged: 0,
        following: new Set(),
        hidden: false,
      };
      this.users.set(userId, u);
    }
    return u;
  }

  allUsers(): UserHabit[] {
    return [...this.users.values()];
  }

  setProfile(userId: string, p: { displayName?: string; dailyGoalCards?: number; freezesPerWeek?: number }) {
    const u = this.user(userId);
    if (p.displayName) u.displayName = p.displayName.slice(0, 40);
    if (p.dailyGoalCards) u.dailyGoalCards = Math.min(200, Math.max(1, p.dailyGoalCards));
    if (p.freezesPerWeek !== undefined) u.freezesPerWeek = Math.min(7, Math.max(0, p.freezesPerWeek));
    return u;
  }

  ingest(userId: string, batch: ActivityBatch) {
    const u = this.user(userId);
    let accepted = 0;
    let verified = 0;
    let goalMetOn: string | undefined;
    for (const e of batch.events) {
      const dedupe = `${e.card_ref}|${e.ts}`;
      if (u.seen.has(dedupe)) continue;
      u.seen.add(dedupe);
      accepted++;
      const r = evaluateDwell(e.words, e.dwell_ms, u.wpm);
      u.wpm = r.updatedWpm;
      if (r.implausible) {
        u.flagged++;
        if (u.flagged >= 20) u.hidden = true;
      }
      const day = localDateKey(new Date(e.ts), batch.tz_offset_min);
      const stat = u.days.get(day) ?? { verifiedCards: 0, skimmedCards: 0, minutes: 0, goalMet: false };
      if (r.verified) {
        stat.verifiedCards++;
        stat.minutes = Math.min(DAILY_MINUTES_CAP, stat.minutes + r.minutes);
        verified++;
      } else {
        stat.skimmedCards++;
      }
      if (!stat.goalMet && stat.verifiedCards >= u.dailyGoalCards) {
        stat.goalMet = true;
        u.streak = recordGoalMet(u.streak, day, u.freezesPerWeek);
        goalMetOn = day;
        this.post(u.userId, "goal_met", `${u.displayName} hit today’s reading goal`);
        if (STREAK_MILESTONES.has(u.streak.current)) {
          this.post(u.userId, "streak_milestone", `${u.displayName} reached a ${u.streak.current}-day streak 🔥`);
        }
      }
      u.days.set(day, stat);
    }
    return { accepted, verified, goalMetOn, streak: u.streak.current, wpm: Math.round(u.wpm) };
  }

  bookFinished(userId: string, title: string) {
    const u = this.user(userId);
    this.post(userId, "book_finished", `${u.displayName} finished ${title.slice(0, 120)} 📚`);
  }

  streakOf(userId: string, today: string) {
    const u = this.user(userId);
    return { current: displayStreak(u.streak, today, u.freezesPerWeek), best: u.streak.best, freezesLeft: u.streak.freezesLeft };
  }

  /** League/leaderboard score for a week: consistency first (active days), then capped minutes. */
  weekScore(userId: string, week: string): { activeDays: number; minutes: number; score: number } {
    const u = this.user(userId);
    let activeDays = 0;
    let minutes = 0;
    for (const [day, stat] of u.days) {
      if (weekKey(day) !== week) continue;
      if (stat.goalMet) activeDays++;
      minutes += stat.minutes;
    }
    return { activeDays, minutes: Math.round(minutes), score: activeDays * 1000 + Math.round(minutes) };
  }

  follow(userId: string, other: string) {
    if (userId !== other) this.user(userId).following.add(other);
  }

  unfollow(userId: string, other: string) {
    this.user(userId).following.delete(other);
  }

  friendsLeaderboard(userId: string, week: string) {
    const ids = [userId, ...this.user(userId).following];
    return ids
      .map((id) => ({ userId: id, name: this.user(id).displayName, ...this.weekScore(id, week) }))
      .sort((a, b) => b.score - a.score);
  }

  feedFor(userId: string, limit = 50) {
    const following = this.user(userId).following;
    return this.feed
      .filter((f) => following.has(f.userId) || f.userId === userId)
      .slice(-limit)
      .reverse()
      .map((f) => ({ id: f.id, userId: f.userId, type: f.type, text: f.text, at: f.at.toISOString(), kudos: f.kudos.size, gaveKudos: f.kudos.has(userId) }));
  }

  /** Kudos only (no dislikes); returns false for unknown or own activities. */
  kudos(userId: string, activityId: string): boolean {
    const item = this.feed.find((f) => f.id === activityId);
    if (!item || item.userId === userId) return false;
    item.kudos.add(userId);
    return true;
  }

  private post(userId: string, type: FeedItem["type"], text: string) {
    this.feed.push({ id: randomUUID(), userId, type, text, at: new Date(), kudos: new Set() });
    if (this.feed.length > 10_000) this.feed.splice(0, this.feed.length - 10_000);
  }
}
