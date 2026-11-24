import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { AccountService } from "../src/account.js";
import { buildApp } from "../src/app.js";
import type { Db } from "../src/db/db.js";
import { ActivityService } from "../src/habit/activity.js";
import { localDateKey } from "../src/habit/engine.js";
import { SegmentService } from "../src/segmentation/service.js";
import { SqlJobStore, SqlQuotaStore, SqlSegmentCache, SqlUsageLog } from "../src/stores/sql.js";
import { testDb } from "./helpers.js";

let db: Db;
beforeEach(async () => {
  db = await testDb();
});
afterEach(() => db.close());

function app() {
  const quota = new SqlQuotaStore(db);
  const segments = new SegmentService({
    cache: new SqlSegmentCache(db),
    quota,
    usage: new SqlUsageLog(db),
    jobs: new SqlJobStore(db),
    model: { structure: async () => { throw new Error("unused"); }, present: async () => { throw new Error("unused"); } },
  });
  return buildApp({ db, segments, quota, publicBaseUrl: "https://cloro.app" });
}

const phone = { "x-device-id": "aaaaaaaaaaaaaaaa" };
const tablet = { "x-device-id": "dddddddddddddddd" };
const ravi = { "x-device-id": "bbbbbbbbbbbbbbbb" };
const ASHA = "device:aaaaaaaaaaaaaaaa";

type App = ReturnType<typeof app>;
const get = (a: App, url: string, headers: Record<string, string>) => a.inject({ method: "GET", url, headers });
const put = (a: App, url: string, headers: Record<string, string>, payload: Record<string, unknown>) =>
  a.inject({ method: "PUT", url, headers, payload });

const today = localDateKey(new Date(), 0);
const day = (n: number) => {
  const d = new Date(`${today}T12:00:00.000Z`);
  d.setUTCDate(d.getUTCDate() - n);
  return d.toISOString().slice(0, 10);
};

describe("reading stats from the phone", () => {
  it("keeps every day read before the server existed, then only what changed", async () => {
    const a = app();
    // The first time the phone meets the server: its whole history.
    const history = Array.from({ length: 30 }, (_, i) => ({ day: day(i), cards: 10, skimmed: 2, minutes: 12.5, words: 2750 }));
    const first = await put(a, "/v1/me/stats", phone, {
      days: history,
      totals: { books_finished: 3, streak: 30, best_streak: 41, as_of: today, wpm: 236, words_learned: 18 },
    });
    expect(first.statusCode).toBe(200);
    expect(first.json()).toEqual({ ok: true, days: 30 });

    let me = (await get(a, "/v1/me", phone)).json();
    expect(me.stats).toEqual({
      days_read: 30,
      cards: 300,
      minutes: 375,
      words: 82500,
      pages: 300,
      books_finished: 3,
      streak: 30,
      best_streak: 41,
      words_learned: 18,
    });

    // Today grows: its row is replaced, not added to.
    await put(a, "/v1/me/stats", phone, { days: [{ day: today, cards: 14, skimmed: 2, minutes: 20, words: 3850 }] });
    me = (await get(a, "/v1/me", phone)).json();
    expect(me.stats.cards).toBe(304);
    expect(me.stats.words).toBe(83600);
    expect(me.stats.books_finished, "totals left out stay as they were").toBe(3);
  });

  it("adds up a reader's phones day by day, and keeps the best of their totals", async () => {
    const a = app();
    await put(a, "/v1/me/stats", phone, {
      days: [{ day: today, cards: 5, skimmed: 0, minutes: 6, words: 1100 }],
      totals: { books_finished: 2, streak: 4, best_streak: 9, as_of: today },
    });
    // The same account on a tablet (signed in, the tablet's device id differs).
    await db.query("insert into aliases (alias, user_id) values ('fb:asha', $1)", [ASHA]);
    const svc = new ActivityService(db);
    await svc.saveStats(ASHA, "dddddddddddddddd", {
      days: [
        { day: today, cards: 3, skimmed: 1, minutes: 4, words: 550 },
        { day: day(1), cards: 2, skimmed: 0, minutes: 3, words: 275 },
      ],
      totals: { books_finished: 1, streak: 6, best_streak: 6, as_of: today, weekly: false, wpm: 0, words_learned: 0 },
    });
    const s = await svc.statsOf(ASHA, today);
    expect(s).toMatchObject({ days_read: 2, cards: 10, minutes: 13, words: 1925, pages: 7, books_finished: 2, streak: 6, best_streak: 9 });
    void tablet;
  });

  it("a phone's streak counts only while fresh; the public profile shows it with books finished", async () => {
    const a = app();
    await put(a, "/v1/me/profile", phone, { display_name: "Asha", handle: "asha.reads" });
    await put(a, "/v1/me/stats", phone, { totals: { books_finished: 5, streak: 12, best_streak: 20, as_of: today } });
    let profile = (await get(a, "/v1/users/@asha.reads", ravi)).json();
    expect(profile.streak).toEqual({ current: 12, best: 20 });
    expect(profile.books_finished).toBe(5);

    // Counted three days ago and not since: that streak may well have ended.
    await put(a, "/v1/me/stats", phone, { totals: { books_finished: 5, streak: 12, best_streak: 20, as_of: day(3) } });
    profile = (await get(a, "/v1/users/@asha.reads", ravi)).json();
    expect(profile.streak).toEqual({ current: 0, best: 20 });
  });

  it("refuses nonsense, and is left out of nothing: export and deletion include it", async () => {
    const a = app();
    expect((await put(a, "/v1/me/stats", phone, { days: [{ day: "yesterday", cards: 1, skimmed: 0, minutes: 1, words: 1 }] })).statusCode).toBe(400);
    expect((await put(a, "/v1/me/stats", phone, { days: [{ day: today, cards: -1, skimmed: 0, minutes: 1, words: 1 }] })).statusCode).toBe(400);
    expect((await put(a, "/v1/me/stats", phone, { days: [{ day: today, cards: 1, skimmed: 0, minutes: 5000, words: 1 }] })).statusCode).toBe(400);

    await put(a, "/v1/me/stats", phone, {
      days: [{ day: today, cards: 4, skimmed: 1, minutes: 5, words: 900 }],
      totals: { books_finished: 1, streak: 1, best_streak: 1, as_of: today },
    });
    const accounts = new AccountService(db);
    const exported = (await accounts.export(ASHA))!;
    expect(exported.reading_stats).toHaveLength(1);
    expect((exported.user as unknown as { totals: Record<string, unknown> }).totals).toHaveProperty("aaaaaaaaaaaaaaaa");
    expect(await accounts.delete(ASHA)).toBe(true);
    expect(await db.query("select 1 from reading_stats where user_id = $1", [ASHA])).toHaveLength(0);
  });
});

describe("a daily goal in minutes", () => {
  it("meets the goal on minutes read, not on ten cards", async () => {
    const a = app();
    await put(a, "/v1/me/profile", phone, { display_name: "Asha", daily_goal_cards: 10, goal_unit: "minutes", daily_goal_minutes: 3 });
    const svc = new ActivityService(db);
    // Six careful cards of 120 words in 30 s each: three minutes, well short of ten cards.
    const r = await svc.ingest(ASHA, {
      tz_offset_min: 0,
      events: Array.from({ length: 6 }, (_, i) => ({
        book_id: "b",
        card_ref: `c${i}`,
        words: 120,
        dwell_ms: 30000,
        ts: `${today}T10:0${i}:00.000Z`,
      })),
    });
    expect(r.goalMetOn).toBe(today);
    expect(r.streak).toBe(1);
    const me = (await get(a, "/v1/me", phone)).json();
    expect(me.goal_unit).toBe("minutes");
    expect(me.daily_goal_minutes).toBe(3);
  });
});
