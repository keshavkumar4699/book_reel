import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { describe, expect, it } from "vitest";

import { openDb, poolConfig } from "../src/db/db.js";
import { ActivityService } from "../src/habit/activity.js";

describe("database", () => {
  it("creates a missing data directory and keeps data across reopen", async () => {
    const root = mkdtempSync(join(tmpdir(), "bookreel-db-"));
    const dir = join(root, "nested", "pglite");
    try {
      const first = await openDb(dir);
      const code = (await new ActivityService(first).user("device:abc")).invite_code;
      await first.close();
      const second = await openDb(dir); // migrations must not re-run
      expect((await new ActivityService(second).user("device:abc")).invite_code).toBe(code);
      await second.close();
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });

  it("lets a sleeping database stay asleep: idle connections close, a waking one is waited for", () => {
    const url = "postgres://u:p@ep-quiet-sun.ap-southeast-1.aws.neon.tech/cloro?sslmode=require";
    const c = poolConfig(url, {});
    expect(c.connectionString).toBe(url);
    expect(c.max).toBe(5);
    expect(c.idleTimeoutMillis).toBe(10_000);
    expect(c.connectionTimeoutMillis).toBe(15_000);
    expect(poolConfig(url, { DATABASE_POOL_MAX: "2" }).max).toBe(2);
    expect(poolConfig(url, { DATABASE_POOL_MAX: "lots" }).max).toBe(5);
  });
});
