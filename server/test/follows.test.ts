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

const asha = { "x-device-id": "aaaaaaaaaaaaaaaa" };
const ravi = { "x-device-id": "bbbbbbbbbbbbbbbb" };
const meera = { "x-device-id": "cccccccccccccccc" };
const RAVI = "device:bbbbbbbbbbbbbbbb";
const ASHA = "device:aaaaaaaaaaaaaaaa";

type App = ReturnType<typeof app>;
const get = (a: App, url: string, headers: Record<string, string>) => a.inject({ method: "GET", url, headers });
const post = (a: App, url: string, headers: Record<string, string>, payload?: Record<string, unknown>) =>
  a.inject({ method: "POST", url, headers, payload: payload ?? {} });
const put = (a: App, url: string, headers: Record<string, string>, payload: Record<string, unknown>) =>
  a.inject({ method: "PUT", url, headers, payload });

async function readers(a: App) {
  await put(a, "/v1/me/profile", asha, { display_name: "Asha", handle: "asha.reads", pronouns: "she/her", bio: "Classics at dawn" });
  await put(a, "/v1/me/profile", ravi, { display_name: "Ravi", handle: "ravi" });
  await put(a, "/v1/me/profile", meera, { display_name: "Meera" });
}

describe("follows", () => {
  it("following is one way, with public counts", async () => {
    const a = app();
    await readers(a);
    expect((await post(a, `/v1/social/follow/${RAVI}`, asha)).statusCode).toBe(200);
    expect((await post(a, `/v1/social/follow/${RAVI}`, asha)).statusCode).toBe(200); // twice is once

    const me = (await get(a, "/v1/me", asha)).json();
    expect([me.followers, me.following]).toEqual([0, 1]);
    const r = (await get(a, "/v1/me", ravi)).json();
    expect([r.followers, r.following]).toEqual([1, 0]);

    // Ravi's feed doesn't show Asha: he doesn't follow her.
    const profile = (await get(a, `/v1/users/${RAVI}`, asha)).json();
    expect(profile).toMatchObject({ display_name: "Ravi", handle: "ravi", followers: 1, following: 0, you_follow: true, follows_you: false, me: false });

    expect((await a.inject({ method: "DELETE", url: `/v1/social/follow/${RAVI}`, headers: asha })).statusCode).toBe(200);
    expect((await get(a, "/v1/me", ravi)).json().followers).toBe(0);
  });

  it("follow by @username, in any case; not yourself, not someone unknown", async () => {
    const a = app();
    await readers(a);
    const res = await post(a, "/v1/social/follow-handle", ravi, { handle: "@Asha.Reads" });
    expect(res.statusCode).toBe(200);
    expect(res.json().user).toEqual({ user_id: ASHA, display_name: "Asha", handle: "asha.reads", avatar: "", you_follow: true });
    expect((await post(a, "/v1/social/follow-handle", ravi, { handle: "nobody.here" })).statusCode).toBe(404);
    expect((await post(a, "/v1/social/follow-handle", ravi, { handle: "ravi" })).statusCode).toBe(400);
    expect((await post(a, "/v1/social/follow/device:ffffffffffffffff", ravi)).statusCode).toBe(404);
  });

  it("followers and following lists say whom you follow back", async () => {
    const a = app();
    await readers(a);
    await post(a, "/v1/social/follow-handle", ravi, { handle: "asha.reads" });
    await post(a, "/v1/social/follow-handle", meera, { handle: "asha.reads" });
    await post(a, "/v1/social/follow-handle", asha, { handle: "ravi" });

    const followers = (await get(a, "/v1/users/@asha.reads/followers", asha)).json().items;
    expect(followers.map((p: { display_name: string; you_follow: boolean }) => [p.display_name, p.you_follow])).toEqual([
      ["Meera", false],
      ["Ravi", true],
    ]);
    const following = (await get(a, "/v1/users/me/following", asha)).json().items;
    expect(following.map((p: { handle: string }) => p.handle)).toEqual(["ravi"]);
    // Seen by someone else: "you_follow" is about the viewer.
    const seenByMeera = (await get(a, `/v1/users/${ASHA}/followers`, meera)).json().items;
    expect(seenByMeera.map((p: { you_follow: boolean }) => p.you_follow)).toEqual([false, false]);
    expect((await get(a, "/v1/users/@nobody.here/followers", asha)).statusCode).toBe(404);
  });

  it("a public profile shows genres (up to 3), what they're reading, and their streak", async () => {
    const a = app();
    await readers(a);
    const saved = await put(a, "/v1/me/profile", asha, {
      genres: ["Classics", "Poetry", "History", "Science"],
      reading: "  Pride   and Prejudice ",
    });
    expect(saved.json()).toMatchObject({ genres: ["Classics", "Poetry", "History"], reading: "Pride and Prejudice" });
    await post(a, "/v1/social/follow-handle", asha, { handle: "ravi" });
    const p = (await get(a, "/v1/users/@ASHA.READS", ravi)).json();
    expect(p).toMatchObject({
      display_name: "Asha",
      pronouns: "she/her",
      bio: "Classics at dawn",
      genres: ["Classics", "Poetry", "History"],
      reading: "Pride and Prejudice",
      followers: 0,
      following: 1,
      you_follow: false,
      follows_you: true,
      streak: { current: 0, best: 0 },
    });
    expect(p).not.toHaveProperty("invite_code");
    expect((await get(a, "/v1/users/me", asha)).json().me).toBe(true);
  });

  it("hidden readers can't be seen or followed, and don't count", async () => {
    const a = app();
    await readers(a);
    await post(a, "/v1/social/follow-handle", meera, { handle: "asha.reads" });
    await db.query("update users set hidden = true where id = $1", ["device:cccccccccccccccc"]);
    expect((await get(a, "/v1/me", asha)).json().followers).toBe(0);
    expect((await get(a, "/v1/users/device:cccccccccccccccc", asha)).statusCode).toBe(404);
    expect((await post(a, "/v1/social/follow/device:cccccccccccccccc", asha)).statusCode).toBe(404);
    expect((await get(a, "/v1/users/me", meera)).statusCode).toBe(200);
  });

  it("an invite code is personal: inviter and invitee follow each other", async () => {
    const a = app();
    await readers(a);
    const code = (await get(a, "/v1/me", asha)).json().invite_code;
    const res = await post(a, "/v1/social/follow-code", ravi, { code });
    expect(res.json().friend.name).toBe("Asha");
    expect((await get(a, "/v1/me", asha)).json()).toMatchObject({ followers: 1, following: 1 });
    const page = await get(a, `/i/${code}`, {});
    expect(page.body).toContain("Profile → Find people");
  });
});
