import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { buildApp } from "../src/app.js";
import type { Db } from "../src/db/db.js";
import { SegmentService } from "../src/segmentation/service.js";
import { SqlJobStore, SqlQuotaStore, SqlSegmentCache, SqlUsageLog } from "../src/stores/sql.js";
import { testDb } from "./helpers.js";

let db: Db;
beforeEach(async () => {
  db = await testDb();
});
afterEach(() => db.close());

function app(supportEmail?: string) {
  const quota = new SqlQuotaStore(db);
  const segments = new SegmentService({
    cache: new SqlSegmentCache(db),
    quota,
    usage: new SqlUsageLog(db),
    jobs: new SqlJobStore(db),
    model: { structure: async () => { throw new Error("unused"); }, present: async () => { throw new Error("unused"); } },
  });
  return buildApp({ db, segments, quota, supportEmail, publicBaseUrl: "https://cloro.app" });
}

const asha = { "x-device-id": "aaaaaaaaaaaaaaaa" };
const ravi = { "x-device-id": "bbbbbbbbbbbbbbbb" };
const ASHA = "device:aaaaaaaaaaaaaaaa";
const RAVI = "device:bbbbbbbbbbbbbbbb";

type App = ReturnType<typeof app>;
type H = Record<string, string>;
const req = (a: App, method: "GET" | "POST" | "PUT" | "DELETE", url: string, headers: H, payload?: Record<string, unknown>) =>
  a.inject({ method, url, headers, ...(payload ? { payload } : {}) });

const session = (id: string) => ({
  client_id: id,
  started_at: new Date().toISOString(),
  minutes: 10,
  cards: 6,
  book: { title: "Emma", author: "Jane Austen" },
  progress: 0.2,
});

/** Two readers with data in every table. */
async function twoReaders(a: App) {
  await req(a, "PUT", "/v1/me/profile", asha, { display_name: "Asha", handle: "asha", bio: "Classics", genres: ["Classics"], reading: "Emma" });
  await req(a, "PUT", "/v1/me/profile", ravi, { display_name: "Ravi", handle: "ravi" });
  await req(a, "POST", "/v1/social/follow-handle", asha, { handle: "ravi" });
  await req(a, "POST", "/v1/social/follow-handle", ravi, { handle: "asha" });
  const now = new Date().toISOString();
  await req(a, "POST", "/v1/activity/batch", asha, { events: [1, 2].map((i) => ({ book_id: "b", card_ref: `c${i}`, words: 120, dwell_ms: 30000, ts: now })) });
  await req(a, "POST", "/v1/activity/batch", ravi, { events: [1, 2].map((i) => ({ book_id: "b", card_ref: `r${i}`, words: 120, dwell_ms: 30000, ts: now })) });
  const ashaItem = (await req(a, "POST", "/v1/activities/session", asha, session("s-asha-0001"))).json().id;
  const raviItem = (await req(a, "POST", "/v1/activities/session", ravi, session("s-ravi-0001"))).json().id;
  await req(a, "POST", `/v1/activities/${raviItem}/comments`, asha, { text: "Lovely" });
  await req(a, "POST", `/v1/activities/${ashaItem}/comments`, ravi, { text: "Thanks for the tip" });
  await req(a, "POST", `/v1/activities/${raviItem}/kudos`, asha);
  await req(a, "POST", `/v1/activities/${ashaItem}/kudos`, ravi);
  await req(a, "PUT", "/v1/sync", asha, { items: [{ kind: "highlight", id: "h1", updated_at: 1, data: { text: "a line" } }] });
  await req(a, "POST", "/v1/share", asha, { type: "progress", headline: "7 days in a row" });
  await db.query("insert into aliases (alias, user_id) values ('fb:asha', $1)", [ASHA]);
  await db.query("insert into league_divisions (user_id, division) values ($1, 1) on conflict do nothing", [ASHA]);
  await db.query("insert into tts_usage (user_id, day, chars) values ($1, '2026-11-13', 500)", [ASHA]);
  await db.query("insert into mood_usage (user_id, day, calls) values ($1, '2026-11-13', 2)", [ASHA]);
  await db.query("insert into quota_books (user_id, period, content_hash) values ($1, '2026-11', 'h')", [ASHA]);
  await db.query(
    "insert into ai_usage (user_id, model, input_tokens, output_tokens, cost_usd, batch) values ($1, 'claude-haiku-5-5', 10, 10, 0.01, false)",
    [ASHA],
  );
  await db.query("insert into entitlements (purchase_token, user_id, product_id, tier, state) values ('tok', $1, 'bookreel_lite', 'lite', 'active')", [ASHA]);
  return { ashaItem, raviItem };
}

/** Rows naming [id] in every table that can. */
async function rowsFor(id: string) {
  const counts: Record<string, number> = {};
  const tables: [string, string][] = [
    ["users", "id = $1"],
    ["aliases", "user_id = $1"],
    ["reading_days", "user_id = $1"],
    ["reading_events_seen", "user_id = $1"],
    ["follows", "follower = $1 or followee = $1"],
    ["feed_items", "user_id = $1"],
    ["kudos", "user_id = $1"],
    ["comments", "user_id = $1"],
    ["league_divisions", "user_id = $1"],
    ["league_members", "user_id = $1"],
    ["sync_items", "user_id = $1"],
    ["shares", "user_id = $1"],
    ["tts_usage", "user_id = $1"],
    ["mood_usage", "user_id = $1"],
    ["quota_books", "user_id = $1"],
    ["batch_jobs", "user_id = $1"],
    ["ai_usage", "user_id = $1"],
    ["entitlements", "user_id = $1"],
  ];
  for (const [t, where] of tables) {
    counts[t] = Number((await db.query<{ n: string | number }>(`select count(*) as n from ${t} where ${where}`, [id]))[0]!.n);
  }
  return counts;
}

describe("your data", () => {
  it("download my data: everything the server keeps about you, and nobody else's private data", async () => {
    const a = app();
    await twoReaders(a);
    const res = await req(a, "GET", "/v1/me/export", asha);
    expect(res.statusCode).toBe(200);
    expect(res.headers["content-disposition"]).toContain("cloro-export.json");
    const d = res.json();
    expect(d.user).toMatchObject({ id: ASHA, display_name: "Asha", handle: "asha", bio: "Classics", genres: ["Classics"], reading: "Emma" });
    expect(d.reading_days).toHaveLength(1);
    expect(d.following.map((p: { handle: string }) => p.handle)).toEqual(["ravi"]);
    expect(d.followers.map((p: { handle: string }) => p.handle)).toEqual(["ravi"]);
    expect(d.activities.map((x: { type: string }) => x.type)).toEqual(["session"]);
    expect(d.comments.map((x: { text: string }) => x.text)).toEqual(["Lovely"]);
    expect(d.kudos_given).toHaveLength(1);
    expect(d.notebook).toEqual([expect.objectContaining({ kind: "highlight", item_id: "h1", data: { text: "a line" } })]);
    expect(d.shares).toHaveLength(1);
    expect(d.subscriptions).toEqual([expect.objectContaining({ product_id: "bookreel_lite", tier: "lite" })]);
    expect(d.subscriptions[0]).not.toHaveProperty("purchase_token");
    expect(d.usage.read_aloud_characters).toHaveLength(1);
    // Ravi's comment on Asha's session is his, not hers.
    expect(JSON.stringify(d)).not.toContain("Thanks for the tip");
  });

  it("delete account: every row about you goes, in one step; the other reader keeps theirs", async () => {
    const a = app();
    const { raviItem } = await twoReaders(a);
    const before = await rowsFor(ASHA);
    for (const [t, n] of Object.entries(before)) {
      if (t !== "batch_jobs") expect(n, `${t} has data before`).toBeGreaterThan(0);
    }
    const raviBefore = await rowsFor(RAVI);
    const groupBefore = (await db.query<{ members: number }>("select members from league_groups"))[0]!.members;

    expect((await req(a, "DELETE", "/v1/me", asha)).statusCode).toBe(204);

    expect(await rowsFor(ASHA)).toEqual(Object.fromEntries(Object.keys(before).map((t) => [t, 0])));
    // AI costs stay for accounting, without her; the purchase stays with Google, unlinked.
    expect((await db.query("select * from ai_usage where user_id = 'deleted'")).length).toBe(1);
    expect((await db.query<{ user_id: string | null }>("select user_id from entitlements where purchase_token = 'tok'"))[0]!.user_id).toBeNull();
    expect((await db.query<{ members: number }>("select members from league_groups"))[0]!.members).toBe(groupBefore - 1);

    // Ravi keeps his own data, minus what was Asha's.
    const raviAfter = await rowsFor(RAVI);
    expect(raviAfter.users).toBe(1);
    expect(raviAfter.feed_items).toBe(raviBefore.feed_items);
    expect(raviAfter.follows).toBe(0);
    expect(raviAfter.comments, "his comment on her session went with it").toBe(0);
    const comments = (await req(a, "GET", `/v1/activities/${raviItem}/comments`, ravi)).json().items;
    expect(comments, "her comment on his session is gone").toEqual([]);
    const feed = (await req(a, "GET", "/v1/feed", ravi)).json().items;
    expect(feed.map((f: { userId: string }) => f.userId)).toEqual([RAVI]);
    expect(feed[0].kudos).toBe(0);
    expect((await req(a, "GET", "/v1/users/@asha", ravi)).statusCode).toBe(404);

    // Asking again is fine; coming back starts a new, empty account.
    expect((await req(a, "DELETE", "/v1/me", asha)).statusCode).toBe(204);
    const fresh = (await req(a, "GET", "/v1/me", asha)).json();
    expect(fresh).toMatchObject({ display_name: "Reader", handle: null, followers: 0, following: 0 });
  });

  it("a web page explains how to delete an account (for Google Play)", async () => {
    const page = await req(app("help@cloro.app"), "GET", "/account/delete", {});
    expect(page.statusCode).toBe(200);
    expect(page.headers["content-type"]).toContain("text/html");
    expect(page.body).toContain("Delete your Cloro account");
    expect(page.body).toContain("Settings → You → Delete account");
    expect(page.body).toContain("mailto:help@cloro.app");
    expect((await req(app(), "GET", "/account/delete", {})).body).not.toContain("mailto:");
    expect((await req(app('<script>"x"@y'), "GET", "/account/delete", {})).body).not.toContain("<script>");
  });
});
