import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { describe, expect, it } from "vitest";

import { openDb } from "../src/db/db.js";
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
});
