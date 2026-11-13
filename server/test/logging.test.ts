import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { buildApp } from "../src/app.js";
import type { Db } from "../src/db/db.js";
import { cloudLoggerOptions, ERROR_EVENT_TYPE } from "../src/logging.js";
import { SegmentService } from "../src/segmentation/service.js";
import { SqlJobStore, SqlQuotaStore, SqlSegmentCache, SqlUsageLog } from "../src/stores/sql.js";
import { testDb } from "./helpers.js";

let db: Db;
beforeEach(async () => {
  db = await testDb();
});
afterEach(async () => {
  await db.close().catch(() => {});
});

/** The app with Cloud Run's logger, writing into [lines]. */
function app(lines: Record<string, unknown>[]) {
  const quota = new SqlQuotaStore(db);
  const segments = new SegmentService({
    cache: new SqlSegmentCache(db),
    quota,
    usage: new SqlUsageLog(db),
    jobs: new SqlJobStore(db),
    model: { structure: async () => { throw new Error("unused"); }, present: async () => { throw new Error("unused"); } },
  });
  const stream = { write: (l: string) => void lines.push(JSON.parse(l) as Record<string, unknown>) };
  return buildApp({ db, segments, quota, logger: { ...cloudLoggerOptions, level: "warn", stream } });
}

const device = { "x-device-id": "aaaaaaaaaaaaaaaa" };

describe("logs for Google Cloud", () => {
  it("an app crash report becomes an Error Reporting event, without the reader's id", async () => {
    const lines: Record<string, unknown>[] = [];
    const a = app(lines);
    const res = await a.inject({
      method: "POST",
      url: "/v1/errors",
      headers: device,
      payload: { message: "Null check operator used on a null value", stack: "#0 ReaderScreen.build (reader_screen.dart:42)", version: "1.0.0+57" },
    });
    expect(res.statusCode).toBe(204);
    const e = lines.find((l) => l["@type"] === ERROR_EVENT_TYPE)!;
    expect(e).toMatchObject({
      severity: "ERROR",
      message: "Null check operator used on a null value",
      serviceContext: { service: "cloro-app", version: "1.0.0+57" },
      context: { platform: "android" },
    });
    expect(e.stack_trace).toContain("reader_screen.dart:42");
    expect(JSON.stringify(lines)).not.toContain("aaaaaaaaaaaaaaaa");
    // No account was created for it.
    expect((await db.query("select * from users")).length).toBe(0);
  });

  it("crash reports are checked and limited", async () => {
    const a = app([]);
    const send = (payload: Record<string, unknown>) => a.inject({ method: "POST", url: "/v1/errors", headers: device, payload });
    expect((await send({ message: "x", book_text: "a whole page" })).statusCode).toBe(400);
    expect((await send({ message: "x".repeat(501) })).statusCode).toBe(400);
    // Every attempt counts, the two refused ones included: 30 an hour.
    for (let i = 0; i < 28; i++) expect((await send({ message: `e${i}` })).statusCode).toBe(204);
    expect((await send({ message: "one too many" })).statusCode).toBe(429);
  });

  it("a server error is reported with its stack; the client just sees 'internal'", async () => {
    const lines: Record<string, unknown>[] = [];
    const a = app(lines);
    await db.close(); // every query now fails
    const res = await a.inject({ url: "/v1/me", headers: device });
    expect(res.statusCode).toBe(500);
    expect(res.json()).toEqual({ error: "internal" });
    const e = lines.find((l) => l["@type"] === ERROR_EVENT_TYPE)!;
    expect(e).toMatchObject({ severity: "ERROR", serviceContext: { service: "cloro-api" }, context: { httpRequest: { method: "GET", url: "/v1/me" } } });
    expect(String(e.stack_trace)).toMatch(/Error/);
  });
});
