import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { buildApp } from "../src/app.js";
import type { Db } from "../src/db/db.js";
import { FeedService } from "../src/habit/feed.js";
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
  return buildApp({ db, segments, quota });
}

const asha = { "x-device-id": "aaaaaaaaaaaaaaaa" };
const ravi = { "x-device-id": "bbbbbbbbbbbbbbbb" };
const meera = { "x-device-id": "cccccccccccccccc" };
const ASHA = "device:aaaaaaaaaaaaaaaa";

type App = ReturnType<typeof app>;
type H = Record<string, string>;
const get = (a: App, url: string, headers: H) => a.inject({ method: "GET", url, headers });
const post = (a: App, url: string, headers: H, payload: Record<string, unknown> = {}) => a.inject({ method: "POST", url, headers, payload });

const session = (over: Record<string, unknown> = {}) => ({
  client_id: "s-asha-0001",
  started_at: "2026-11-12T20:00:00Z",
  minutes: 12,
  cards: 8,
  book: { title: "Pride and Prejudice", author: "Jane Austen" },
  progress: 0.34,
  mood: "cozy",
  quote: "It is a truth universally acknowledged…",
  ...over,
});

async function readers(a: App) {
  await a.inject({ method: "PUT", url: "/v1/me/profile", headers: asha, payload: { display_name: "Asha", handle: "asha", avatar: "🦉" } });
  await a.inject({ method: "PUT", url: "/v1/me/profile", headers: ravi, payload: { display_name: "Ravi" } });
  await a.inject({ method: "PUT", url: "/v1/me/profile", headers: meera, payload: { display_name: "Meera" } });
  await post(a, "/v1/social/follow-handle", ravi, { handle: "asha" });
}

describe("Today feed", () => {
  it("a session is one card that grows as it's re-uploaded, with its stats", async () => {
    const a = app();
    await readers(a);
    expect((await post(a, "/v1/activities/session", asha, session({ minutes: 4, cards: 3 }))).statusCode).toBe(200);
    expect((await post(a, "/v1/activities/session", asha, session())).statusCode).toBe(200);

    const items = (await get(a, "/v1/feed", ravi)).json().items;
    expect(items).toHaveLength(1);
    expect(items[0]).toMatchObject({
      type: "session",
      text: "Asha read Pride and Prejudice",
      at: "2026-11-12T20:00:00.000Z",
      author: { name: "Asha", handle: "asha", avatar: "🦉" },
      data: { book: { title: "Pride and Prejudice", author: "Jane Austen" }, minutes: 12, cards: 8, progress: 0.34, mood: "cozy" },
      kudos: 0,
      comments: 0,
      mine: false,
    });
    expect(items[0].data.quote).toContain("truth universally");
    // Your own feed has it too; Meera follows no one.
    expect((await get(a, "/v1/feed", asha)).json().items[0].mine).toBe(true);
    expect((await get(a, "/v1/feed", meera)).json().items).toEqual([]);
  });

  it("sessions are checked: no empty ones, no unknown moods, no extra fields", async () => {
    const a = app();
    await readers(a);
    expect((await post(a, "/v1/activities/session", asha, session({ minutes: 0.5, cards: 0 }))).json()).toEqual({ id: null });
    expect((await post(a, "/v1/activities/session", asha, session({ mood: "angry" }))).statusCode).toBe(400);
    expect((await post(a, "/v1/activities/session", asha, session({ text: "a whole chapter" }))).statusCode).toBe(400);
    expect((await post(a, "/v1/activities/session", asha, session({ client_id: "x" }))).statusCode).toBe(400);
    expect((await post(a, "/v1/activities/session", asha, session({ quote: "x".repeat(281) }))).statusCode).toBe(400);
  });

  it("pages back with ?before=, newest first", async () => {
    const a = app();
    await readers(a);
    for (let i = 0; i < 25; i++) {
      const at = new Date(Date.UTC(2026, 10, 1, 8 + i)).toISOString();
      await post(a, "/v1/activities/session", asha, session({ client_id: `s-asha-${String(i).padStart(4, "0")}`, started_at: at }));
    }
    const first = (await get(a, "/v1/feed", ravi)).json().items;
    expect(first).toHaveLength(20);
    const next = (await get(a, `/v1/feed?before=${encodeURIComponent(first[19].at)}`, ravi)).json().items;
    expect(next).toHaveLength(5);
    expect(new Date(next[0].at).getTime()).toBeLessThan(new Date(first[19].at).getTime());
  });

  it("comments: readers who can see an activity comment on it; authors can tidy up", async () => {
    const a = app();
    await readers(a);
    const id = (await post(a, "/v1/activities/session", asha, session())).json().id;

    const c1 = await post(a, `/v1/activities/${id}/comments`, ravi, { text: "  Love   this one! " });
    expect(c1.statusCode).toBe(200);
    expect(c1.json().comment.text).toBe("Love this one!");
    await post(a, `/v1/activities/${id}/comments`, asha, { text: "Thank you 🙂" });
    expect((await post(a, `/v1/activities/${id}/comments`, meera, { text: "hi" })).statusCode, "Meera doesn't follow Asha").toBe(404);
    expect((await post(a, `/v1/activities/${id}/comments`, ravi, { text: "   " })).statusCode).toBe(400);
    expect((await post(a, `/v1/activities/${id}/comments`, ravi, { text: "x".repeat(301) })).statusCode).toBe(400);

    const list = (await get(a, `/v1/activities/${id}/comments`, ravi)).json().items;
    expect(list.map((c: { name: string; text: string; mine: boolean; can_delete: boolean }) => [c.name, c.text, c.mine, c.can_delete])).toEqual([
      ["Ravi", "Love this one!", true, true],
      ["Asha", "Thank you 🙂", false, false],
    ]);
    expect((await get(a, "/v1/feed", ravi)).json().items[0].comments).toBe(2);
    expect((await get(a, `/v1/activities/${id}/comments`, meera)).statusCode).toBe(404);

    // Ravi can't delete Asha's comment; Asha can delete any comment on her session.
    const ashas = (await get(a, `/v1/activities/${id}/comments`, asha)).json().items;
    expect(ashas.every((c: { can_delete: boolean }) => c.can_delete)).toBe(true);
    expect((await a.inject({ method: "DELETE", url: `/v1/comments/${ashas[1].id}`, headers: ravi })).statusCode).toBe(404);
    expect((await a.inject({ method: "DELETE", url: `/v1/comments/${ashas[0].id}`, headers: asha })).statusCode).toBe(200);
    expect((await get(a, `/v1/activities/${id}/comments`, asha)).json().items).toHaveLength(1);
  });

  it("kudos only on activities you can see, never your own", async () => {
    const a = app();
    await readers(a);
    const id = (await post(a, "/v1/activities/session", asha, session())).json().id;
    expect((await post(a, `/v1/activities/${id}/kudos`, ravi)).statusCode).toBe(200);
    expect((await post(a, `/v1/activities/${id}/kudos`, meera)).statusCode).toBe(404);
    expect((await post(a, `/v1/activities/${id}/kudos`, asha)).statusCode).toBe(404);
    expect((await get(a, "/v1/feed", ravi)).json().items[0]).toMatchObject({ kudos: 1, gaveKudos: true });
  });

  it("a hidden reader's activity leaves other feeds", async () => {
    const a = app();
    await readers(a);
    await post(a, "/v1/activities/session", asha, session());
    await db.query("update users set hidden = true where id = $1", [ASHA]);
    expect((await get(a, "/v1/feed", ravi)).json().items).toEqual([]);
    expect((await get(a, "/v1/feed", asha)).json().items).toHaveLength(1);
  });

  it("a best reading week becomes a milestone, once a week, raised as it grows", async () => {
    const feeds = new FeedService(db);
    await db.query("insert into users (id, display_name, invite_code) values ('u', 'Asha', 'ABCDEFGH')");
    const day = (d: string, minutes: number) =>
      db.query("insert into reading_days (user_id, day, minutes) values ('u', $1, $2) on conflict (user_id, day) do update set minutes = excluded.minutes", [d, minutes]);
    await day("2026-11-02", 40); // week of 2 Nov: 40 min
    await day("2026-11-09", 30); // this week (9 Nov): 30
    await feeds.checkBestWeek("u", "Asha", "2026-11-10");
    expect(await feeds.feedFor("u")).toEqual([]);
    await day("2026-11-10", 15); // 45 > 40
    await feeds.checkBestWeek("u", "Asha", "2026-11-10");
    await day("2026-11-11", 20); // 65
    await feeds.checkBestWeek("u", "Asha", "2026-11-11");
    const items = await feeds.feedFor("u");
    expect(items).toHaveLength(1);
    expect(items[0]).toMatchObject({ type: "best_week", data: { minutes: 65, week: "2026-11-09" } });
    expect(items[0]!.text).toContain("65 min");

    // No earlier week worth beating: no milestone.
    await db.query("insert into users (id, display_name, invite_code) values ('n', 'New', 'HGFEDCBA')");
    await db.query("insert into reading_days (user_id, day, minutes) values ('n', '2026-11-10', 90)");
    await feeds.checkBestWeek("n", "New", "2026-11-10");
    expect(await feeds.feedFor("n")).toEqual([]);
  });
});
