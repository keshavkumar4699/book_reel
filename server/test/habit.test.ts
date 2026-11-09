import { describe, expect, it } from "vitest";

import { ActivityService } from "../src/habit/activity.js";
import { displayStreak, emptyStreak, evaluateDwell, localDateKey, recordGoalMet, weekKey } from "../src/habit/engine.js";
import { LeagueService } from "../src/habit/leagues.js";

describe("habit engine", () => {
  it("verifies dwell like the app and flags implausible speed", () => {
    expect(evaluateDwell(120, 12000, 240).verified).toBe(true);
    expect(evaluateDwell(120, 5000, 240).verified).toBe(false);
    const robot = evaluateDwell(600, 12000, 240); // 3000 wpm, long enough to pass the ratio at a low wpm baseline
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

describe("activity, friends and leagues", () => {
  it("deduplicates events, meets goals and posts to the friend feed", () => {
    const svc = new ActivityService();
    svc.setProfile("a", { displayName: "Asha", dailyGoalCards: 3 });
    const r = readDay(svc, "a", "2026-11-09", 3);
    expect(r).toMatchObject({ accepted: 3, verified: 3, goalMetOn: "2026-11-09", streak: 1 });
    expect(readDay(svc, "a", "2026-11-09", 3).accepted).toBe(0);
    svc.follow("b", "a");
    const feed = svc.feedFor("b");
    expect(feed[0]!.text).toContain("Asha");
    expect(svc.kudos("b", feed[0]!.id)).toBe(true);
    expect(svc.kudos("a", feed[0]!.id)).toBe(false); // no self-kudos
    expect(svc.feedFor("b")[0]!.kudos).toBe(1);
  });

  it("ranks by consistency first, then minutes, and promotes the top 5", () => {
    const svc = new ActivityService();
    const leagues = new LeagueService(svc);
    const week = "2026-11-02";
    for (let u = 0; u < 12; u++) {
      const id = `u${u}`;
      svc.setProfile(id, { dailyGoalCards: 2 });
      for (let d = 0; d < Math.floor(u / 2); d++) readDay(svc, id, `2026-11-0${2 + d}`, 2 + (u % 2));
      leagues.join(id, week);
    }
    const table = leagues.standings("u11", week)!;
    expect(table.division).toBe("Bronze");
    expect(table.rows[0]!.userId).toBe("u11");
    expect(table.rows[0]!.activeDays).toBe(5);
    const { promoted, demoted } = leagues.closeWeek(week);
    expect(promoted).toEqual(["u11", "u10", "u9", "u8", "u7"]);
    expect(demoted).toEqual([]); // nobody below Bronze
    expect(leagues.divisionOf("u11")).toBe(1);
  });
});
