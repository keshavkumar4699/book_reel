import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { buildApp } from "../src/app.js";
import type { Db } from "../src/db/db.js";
import { RateLimiter } from "../src/moderation.js";
import { SegmentService } from "../src/segmentation/service.js";
import { SqlJobStore, SqlQuotaStore, SqlSegmentCache, SqlUsageLog } from "../src/stores/sql.js";
import { testDb } from "./helpers.js";

let db: Db;
beforeEach(async () => {
  db = await testDb();
});
afterEach(() => db.close());

function app(adminToken?: string) {
  const quota = new SqlQuotaStore(db);
  const segments = new SegmentService({
    cache: new SqlSegmentCache(db),
    quota,
    usage: new SqlUsageLog(db),
    jobs: new SqlJobStore(db),
    model: { structure: async () => { throw new Error("unused"); }, present: async () => { throw new Error("unused"); } },
  });
  return buildApp({ db, segments, quota, adminToken, limiter: new RateLimiter() });
}

const asha = { "x-device-id": "aaaaaaaaaaaaaaaa" };
const admin = { "x-admin-token": "secret-token" };

describe("feedback", () => {
  it("is kept until handled, read with the admin token, limited per reader", async () => {
    const a = await app("secret-token");
    const send = (payload: object) => a.inject({ method: "POST", url: "/v1/feedback", headers: asha, payload });
    const ok = await send({ kind: "problem", message: "  The music skips on my phone.  ", contact: "asha@example.com", version: "1.0.0+57", platform: "android", locale: "hi", device: "Android 15" });
    expect(ok.statusCode).toBe(200);
    expect((await send({ message: "" })).statusCode).toBe(400);
    expect((await send({ message: "x".repeat(2001) })).statusCode).toBe(400);
    expect((await send({ kind: "rant", message: "hi" })).statusCode).toBe(400);

    // Not without the token.
    expect((await a.inject({ method: "GET", url: "/v1/admin/feedback" })).statusCode).toBe(404);
    const list = (await a.inject({ method: "GET", url: "/v1/admin/feedback", headers: admin })).json().items;
    expect(list).toHaveLength(1);
    expect(list[0]).toMatchObject({ kind: "problem", message: "The music skips on my phone.", contact: "asha@example.com", app_version: "1.0.0+57", locale: "hi" });
    expect((await a.inject({ method: "POST", url: `/v1/admin/feedback/${list[0].id}/done`, headers: admin })).statusCode).toBe(200);
    expect((await a.inject({ method: "GET", url: "/v1/admin/feedback", headers: admin })).json().items).toHaveLength(0);

    // At most 5 an hour (refused attempts count too: 4 so far).
    expect((await send({ message: "idea" })).statusCode).toBe(200);
    expect((await send({ message: "one more" })).statusCode).toBe(429);
    await a.close();
  });

  it("goes with the account: in the export, and deleted with it", async () => {
    const a = await app();
    await a.inject({ method: "GET", url: "/v1/me", headers: asha });
    await a.inject({ method: "POST", url: "/v1/feedback", headers: asha, payload: { kind: "idea", message: "Dark mode for the share card" } });
    const exported = (await a.inject({ method: "GET", url: "/v1/me/export", headers: asha })).json();
    expect(exported.feedback).toHaveLength(1);
    expect(exported.feedback[0].message).toBe("Dark mode for the share card");
    expect((await a.inject({ method: "DELETE", url: "/v1/me", headers: asha })).statusCode).toBe(204);
    expect(await db.query("select id from feedback")).toHaveLength(0);
    await a.close();
  });
});
