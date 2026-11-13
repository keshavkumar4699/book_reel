import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { buildApp } from "../src/app.js";
import type { Db } from "../src/db/db.js";
import { normalizeText, RateLimiter, TextFilter } from "../src/moderation.js";
import { SegmentService } from "../src/segmentation/service.js";
import { SqlJobStore, SqlQuotaStore, SqlSegmentCache, SqlUsageLog } from "../src/stores/sql.js";
import { testDb } from "./helpers.js";

let db: Db;
beforeEach(async () => {
  db = await testDb();
});
afterEach(() => db.close());

function app(opts: { words?: string[]; adminToken?: string; now?: () => number } = {}) {
  const quota = new SqlQuotaStore(db);
  const segments = new SegmentService({
    cache: new SqlSegmentCache(db),
    quota,
    usage: new SqlUsageLog(db),
    jobs: new SqlJobStore(db),
    model: { structure: async () => { throw new Error("unused"); }, present: async () => { throw new Error("unused"); } },
  });
  return buildApp({
    db,
    segments,
    quota,
    textFilter: new TextFilter(opts.words ?? []),
    adminToken: opts.adminToken,
    limiter: new RateLimiter(opts.now),
  });
}

const asha = { "x-device-id": "aaaaaaaaaaaaaaaa" };
const ravi = { "x-device-id": "bbbbbbbbbbbbbbbb" };
const meera = { "x-device-id": "cccccccccccccccc" };
const kiran = { "x-device-id": "dddddddddddddddd" };
const ASHA = "device:aaaaaaaaaaaaaaaa";
const RAVI = "device:bbbbbbbbbbbbbbbb";

type App = ReturnType<typeof app>;
type H = Record<string, string>;
const req = (a: App, method: "GET" | "POST" | "PUT" | "DELETE", url: string, headers: H, payload?: Record<string, unknown>) =>
  a.inject({ method, url, headers, ...(payload ? { payload } : {}) });

async function readers(a: App) {
  for (const [h, name, handle] of [[asha, "Asha", "asha"], [ravi, "Ravi", "ravi"], [meera, "Meera", "meera"], [kiran, "Kiran", "kiran"]] as const) {
    await req(a, "PUT", "/v1/me/profile", h, { display_name: name, handle });
  }
  // Everyone follows Asha; Asha follows Ravi.
  for (const h of [ravi, meera, kiran]) await req(a, "POST", "/v1/social/follow-handle", h, { handle: "asha" });
  await req(a, "POST", "/v1/social/follow-handle", asha, { handle: "ravi" });
  const post = await req(a, "POST", "/v1/activities/session", asha, {
    client_id: "s-asha-0001",
    started_at: new Date().toISOString(),
    minutes: 10,
    cards: 5,
    book: { title: "Emma", author: "Jane Austen" },
  });
  return post.json().id as string;
}

describe("rate limits", () => {
  it("too many comments in a minute: 429 with a retry time; the next minute is fine", async () => {
    let now = 1_000_000;
    const a = app({ now: () => now });
    const id = await readers(a);
    for (let i = 0; i < 10; i++) {
      expect((await req(a, "POST", `/v1/activities/${id}/comments`, ravi, { text: `Nice ${i}` })).statusCode).toBe(200);
    }
    const over = await req(a, "POST", `/v1/activities/${id}/comments`, ravi, { text: "One more" });
    expect(over.statusCode).toBe(429);
    expect(over.json()).toMatchObject({ error: "rate_limited" });
    expect(Number(over.headers["retry-after"])).toBeGreaterThan(0);
    // Others aren't affected; a minute later Ravi can comment again.
    expect((await req(a, "POST", `/v1/activities/${id}/comments`, meera, { text: "Lovely" })).statusCode).toBe(200);
    now += 61_000;
    expect((await req(a, "POST", `/v1/activities/${id}/comments`, ravi, { text: "Again" })).statusCode).toBe(200);
  });

  it("every API request counts against the IP address", () => {
    const l = new RateLimiter(() => 0);
    for (let i = 0; i < 600; i++) l.hit("ip", "1.2.3.4");
    expect(() => l.hit("ip", "1.2.3.4")).toThrow("Too many requests");
    expect(() => l.hit("ip", "5.6.7.8")).not.toThrow();
  });
});

describe("text filter", () => {
  it("no links, no reserved usernames, no listed words (even disguised)", async () => {
    const a = app({ words: ["meanword", "go away loser"] });
    const id = await readers(a);
    const comment = (text: string) => req(a, "POST", `/v1/activities/${id}/comments`, ravi, { text });
    expect((await comment("Read it at www.spam.example")).json()).toMatchObject({ error: "not_allowed", message: "Links aren't allowed here." });
    expect((await comment("visit http://x.y")).statusCode).toBe(400);
    expect((await comment("You are a MEANWORD")).statusCode).toBe(400);
    expect((await comment("m3anw0rd!!")).statusCode).toBe(400);
    expect((await comment("m.e.a.n.w.o.r.d")).statusCode).toBe(400);
    expect((await comment("go away, LOSER")).statusCode).toBe(400);
    expect((await comment("Free money here")).statusCode).toBe(400);
    expect((await comment("A meaningful, wordy chapter.")).statusCode, "ordinary words pass").toBe(200);

    const profile = (b: Record<string, unknown>) => req(a, "PUT", "/v1/me/profile", meera, b);
    expect((await profile({ handle: "cloro_official" })).json().message).toContain("reserved");
    expect((await profile({ handle: "support" })).statusCode).toBe(400);
    expect((await profile({ bio: "DM me at mysite.com" })).statusCode).toBe(400);
    expect((await profile({ display_name: "Meanword" })).statusCode).toBe(400);
    expect((await profile({ bio: "Poetry at dusk" })).statusCode).toBe(200);
  });

  it("normalises look-alike characters and long repeats", () => {
    expect(normalizeText("H3LLOOOO W0rld!")).toBe("helloo worldi");
    expect(normalizeText("Café")).toBe("cafe");
  });
});

describe("blocking", () => {
  it("a block works both ways: no follows, no feed, no profile, no comments", async () => {
    const a = app();
    const id = await readers(a);
    await req(a, "POST", `/v1/activities/${id}/comments`, ravi, { text: "Hello" });
    expect((await req(a, "POST", `/v1/social/block/${RAVI}`, asha)).statusCode).toBe(200);

    // The follows between them are gone, and can't come back either way.
    expect((await req(a, "GET", "/v1/me", asha)).json()).toMatchObject({ followers: 2, following: 0 });
    expect((await req(a, "POST", "/v1/social/follow-handle", ravi, { handle: "asha" })).statusCode).toBe(404);
    expect((await req(a, "POST", `/v1/social/follow/${RAVI}`, asha)).statusCode).toBe(404);
    // Neither sees the other.
    expect((await req(a, "GET", "/v1/users/@asha", ravi)).statusCode).toBe(404);
    expect((await req(a, "GET", "/v1/users/@ravi", asha)).statusCode).toBe(404);
    expect((await req(a, "GET", "/v1/feed", ravi)).json().items).toEqual([]);
    expect((await req(a, "POST", `/v1/activities/${id}/comments`, ravi, { text: "Hi again" })).statusCode).toBe(404);
    expect((await req(a, "POST", `/v1/activities/${id}/kudos`, ravi)).statusCode).toBe(404);
    // Asha no longer sees Ravi's comment on her session; Meera still sees everything else.
    expect((await req(a, "GET", `/v1/activities/${id}/comments`, asha)).json().items).toEqual([]);
    expect((await req(a, "GET", "/v1/users/@asha/followers", asha)).json().items.map((p: { handle: string }) => p.handle).sort()).toEqual(["kiran", "meera"]);

    expect((await req(a, "GET", "/v1/social/blocked", asha)).json().items).toEqual([expect.objectContaining({ user_id: RAVI, handle: "ravi" })]);
    expect((await req(a, "POST", `/v1/social/block/${ASHA}`, asha)).statusCode, "not yourself").toBe(400);

    // Unblocking lets them find each other again (the follows don't come back by themselves).
    await req(a, "DELETE", `/v1/social/block/${RAVI}`, asha);
    expect((await req(a, "GET", "/v1/users/@asha", ravi)).statusCode).toBe(200);
    expect((await req(a, "GET", "/v1/social/blocked", asha)).json().items).toEqual([]);
  });
});

describe("reports", () => {
  it("a comment two readers report is held back; three readers reporting someone hides them until reviewed", async () => {
    const a = app({ adminToken: "s3cret" });
    const id = await readers(a);
    const c = (await req(a, "POST", `/v1/activities/${id}/comments`, ravi, { text: "Rude remark" })).json().comment.id;
    const report = (h: H, type: string, target: string, reason = "harassment") => req(a, "POST", "/v1/reports", h, { type, id: target, reason });

    expect((await report(asha, "comment", c)).statusCode).toBe(200);
    expect((await report(asha, "comment", c)).statusCode, "reporting twice counts once").toBe(200);
    expect((await req(a, "GET", `/v1/activities/${id}/comments`, meera)).json().items).toHaveLength(1);
    await report(meera, "comment", c);
    expect((await req(a, "GET", `/v1/activities/${id}/comments`, meera)).json().items, "held back").toEqual([]);
    expect((await req(a, "GET", `/v1/activities/${id}/comments`, ravi)).json().items, "its author still sees it").toHaveLength(1);
    expect((await req(a, "GET", "/v1/feed", meera)).json().items[0].comments).toBe(0);

    // A third reader reports Ravi himself: three readers, so he's hidden.
    await report(kiran, "user", RAVI, "spam");
    expect((await req(a, "GET", "/v1/users/@ravi", meera)).statusCode).toBe(404);

    // Bad reports.
    expect((await report(asha, "comment", "nope")).statusCode).toBe(404);
    expect((await report(ravi, "user", RAVI)).statusCode, "not yourself").toBe(404);
    expect((await req(a, "POST", "/v1/reports", asha, { type: "user", id: RAVI, reason: "because" })).statusCode).toBe(400);

    // Review: only with the admin token.
    expect((await req(a, "GET", "/v1/admin/reports", asha)).statusCode).toBe(404);
    const admin = { "x-admin-token": "s3cret" };
    const open = (await req(a, "GET", "/v1/admin/reports", admin)).json().items;
    expect(open.map((r: { target_type: string }) => r.target_type).sort()).toEqual(["comment", "comment", "user"]);
    const commentReport = open.find((r: { target_type: string }) => r.target_type === "comment");
    expect(commentReport.comment_text).toBe("Rude remark");
    // The comment report was fair: remove it. The report on Ravi wasn't: restore him.
    expect((await req(a, "POST", `/v1/admin/reports/${commentReport.id}`, admin, { action: "remove" })).statusCode).toBe(200);
    const userReport = open.find((r: { target_type: string }) => r.target_type === "user");
    expect((await req(a, "POST", `/v1/admin/reports/${userReport.id}`, admin, { action: "restore_user" })).statusCode).toBe(200);
    expect((await req(a, "GET", "/v1/admin/reports", admin)).json().items, "both comment reports settled together").toEqual([]);
    expect((await req(a, "GET", "/v1/users/@ravi", meera)).statusCode).toBe(200);
    expect((await req(a, "GET", `/v1/activities/${id}/comments`, ravi)).json().items).toEqual([]);
  });

  it("deleting an account also removes its blocks and reports", async () => {
    const a = app();
    await readers(a);
    await req(a, "POST", `/v1/social/block/${RAVI}`, asha);
    await req(a, "POST", "/v1/reports", meera, { type: "user", id: ASHA, reason: "spam" });
    expect((await req(a, "DELETE", "/v1/me", asha)).statusCode).toBe(204);
    const n = async (sql: string) => Number((await db.query<{ n: string | number }>(sql, [ASHA]))[0]!.n);
    expect(await n("select count(*) as n from blocks where blocker = $1 or blocked = $1")).toBe(0);
    expect(await n("select count(*) as n from reports where reporter = $1 or target_user = $1")).toBe(0);
  });
});
