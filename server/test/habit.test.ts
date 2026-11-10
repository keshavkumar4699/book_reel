import { afterEach, beforeEach, describe, expect, it } from "vitest";

import type { Db } from "../src/db/db.js";
import { ActivityService } from "../src/habit/activity.js";
import { displayStreak, emptyStreak, evaluateDwell, localDateKey, recordGoalMet, weekKey } from "../src/habit/engine.js";
import { LeagueService } from "../src/habit/leagues.js";
import { testDb } from "./helpers.js";

describe("habit engine", () => {
  it("verifies dwell like the app and flags implausible speed", () => {
    expect(evaluateDwell(120, 12000, 240).verified).toBe(true);
    expect(evaluateDwell(120, 5000, 240).verified).toBe(false);
    const robot = evaluateDwell(600, 12000, 240);
    expect(robot.implausible || !robot.verified).toBe(true);
  });

  it("streak freezes cover one missed day", () => {
    let s = recordGoalMet(emptyStreak(1), "2026-11-02", 1);
    s = recordGoalMet(s, "2026-11-04", 1);
    expect(s.current).toBe(2);
    expect(displayStreak(s, "2026-11-07", 1)).toBe(0);
  });

  it("local dates and weeks", () => {
    expect(localDateKey(new Date("2026-11-08T20:00:00Z"), 330)).toBe("2026-11-09"); // IST
    expect(weekKey("2026-11-08")).toBe("2026-11-02");
  });
});

function readDay(svc: ActivityService, user: string, day: string, cards: number) {
  return svc.ingest(user, {
    tz_offset_min: 0,
    events: Array.from({ length: cards }, (_, i) => ({
      book_id: "b",
      card_ref: `c${i}`,
      words: 120,
      dwell_ms: 30000,
      ts: `${day}T10:${String(i).padStart(2, "0")}:00.000Z`,
    })),
  });
}

describe("activity, friends and leagues (Postgres)", () => {
  let db: Db;
  let svc: ActivityService;
  beforeEach(async () => {
    db = await testDb();
    svc = new ActivityService(db);
  });
  afterEach(() => db.close());

  it("deduplicates events, meets goals, persists streaks and posts to the friend feed", async () => {
    await svc.setProfile("a", { displayName: "Asha", dailyGoalCards: 3 });
    expect(await readDay(svc, "a", "2026-11-09", 3)).toMatchObject({ accepted: 3, verified: 3, goalMetOn: "2026-11-09", streak: 1 });
    expect((await readDay(svc, "a", "2026-11-09", 3)).accepted).toBe(0);
    expect((await readDay(svc, "a", "2026-11-10", 3)).streak).toBe(2);
    expect(await svc.streakOf("a", "2026-11-10")).toMatchObject({ current: 2, best: 2 });

    await svc.follow("b", "a");
    const feed = await svc.feedFor("b");
    expect(feed[0]!.text).toContain("Asha");
    expect(await svc.kudos("b", feed[0]!.id)).toBe(true);
    expect(await svc.kudos("a", feed[0]!.id)).toBe(false); // no self-kudos
    expect((await svc.feedFor("b"))[0]).toMatchObject({ kudos: 1, gaveKudos: true });
  });

  it("invite codes create mutual friendships and a friends board", async () => {
    const a = await svc.user("a");
    await svc.setProfile("a", { displayName: "Asha", dailyGoalCards: 2 });
    expect(a.invite_code).toMatch(/^[A-Z2-9]{8}$/);
    expect(await svc.followByCode("b", "nope")).toBeUndefined();
    expect(await svc.followByCode("a", a.invite_code)).toBeUndefined(); // can't befriend yourself
    expect(await svc.followByCode("b", a.invite_code.toLowerCase())).toEqual({ userId: "a", name: "Asha" });
    await readDay(svc, "a", "2026-11-03", 2);
    const board = await svc.friendsLeaderboard("b", "2026-11-02");
    expect(board.map((r) => r.userId)).toEqual(["a", "b"]);
    expect(board[0]).toMatchObject({ activeDays: 1, me: false });
    expect((await svc.friendsLeaderboard("a", "2026-11-02")).map((r) => r.userId)).toContain("b");
  });

  it("ranks by consistency first, then minutes, and promotes the top 5", async () => {
    const leagues = new LeagueService(db, svc);
    const week = "2026-11-02";
    for (let u = 0; u < 12; u++) {
      const id = `u${u}`;
      await svc.setProfile(id, { dailyGoalCards: 2 });
      for (let d = 0; d < Math.floor(u / 2); d++) await readDay(svc, id, `2026-11-0${2 + d}`, 2 + (u % 2));
      await leagues.join(id, week);
    }
    const table = (await leagues.standings("u11", week))!;
    expect(table.division).toBe("Bronze");
    expect(table.rows).toHaveLength(12);
    expect(table.rows[0]).toMatchObject({ userId: "u11", activeDays: 5, me: true, rank: 1 });
    const { promoted, demoted } = await leagues.closeWeek(week);
    expect(promoted).toEqual(["u11", "u10", "u9", "u8", "u7"]);
    expect(demoted).toEqual([]);
    expect(await leagues.divisionOf("u11")).toBe(1);
  });

  it("fills groups up to 24 and then opens a new one", async () => {
    const leagues = new LeagueService(db, svc);
    const groups = new Set<string>();
    for (let u = 0; u < 25; u++) groups.add((await leagues.join(`p${u}`, "2026-11-02"))!);
    expect(groups.size).toBe(2);
  });
});
