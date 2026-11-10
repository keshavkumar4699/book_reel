import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { buildApp } from "../src/app.js";
import type { Db } from "../src/db/db.js";
import { loadCatalog } from "../src/music/catalog.js";
import type { ModelSegmenter } from "../src/segmentation/claudeSegmenter.js";
import { SegmentService } from "../src/segmentation/service.js";
import { SqlQuotaStore, SqlSegmentCache, SqlUsageLog } from "../src/stores/sql.js";
import { testDb } from "./helpers.js";

const good = {
  id: "t1",
  title: "Morning Mist",
  artist: "A",
  url: "https://cdn.example.com/t1.mp3",
  moods: ["calm"],
  energy: 1,
  license: "Licensed for in-app streaming",
  attribution: "A – Morning Mist",
};

describe("music catalog", () => {
  let dir: string;
  beforeEach(() => {
    dir = mkdtempSync(join(tmpdir(), "music-"));
  });
  afterEach(() => rmSync(dir, { recursive: true, force: true }));

  it("loads valid tracks and reports bad entries instead of crashing", () => {
    const path = join(dir, "catalog.json");
    writeFileSync(
      path,
      JSON.stringify({
        tracks: [
          good,
          { ...good, id: "t2", url: "http://insecure.example.com/a.mp3" },
          { ...good, id: "t3", moods: ["angry"] },
          { ...good, id: "t4", license: "" },
          good,
        ],
      }),
    );
    const { tracks, errors } = loadCatalog(path);
    expect(tracks.map((t) => t.id)).toEqual(["t1"]);
    expect(errors).toHaveLength(4);
    expect(loadCatalog(join(dir, "missing.json"))).toEqual({ tracks: [], errors: [] });
  });

  it("the example catalog is valid", () => {
    expect(loadCatalog("music/catalog.example.json").errors).toEqual([]);
  });
});

describe("GET /v1/music/tracks", () => {
  let db: Db;
  beforeEach(async () => {
    db = await testDb();
  });
  afterEach(() => db.close());

  it("is for paid tiers only", async () => {
    const model: ModelSegmenter = {
      structure: async () => {
        throw new Error("unused");
      },
      present: async () => {
        throw new Error("unused");
      },
    };
    const quota = new SqlQuotaStore(db);
    const segments = new SegmentService({ cache: new SqlSegmentCache(db), quota, usage: new SqlUsageLog(db), model });
    const app = buildApp({ db, segments, quota, music: [good as never] });
    const headers = { "x-device-id": "abcdef0123456789" };
    expect((await app.inject({ url: "/v1/music/tracks?tier=free", headers })).statusCode).toBe(403);
    expect((await app.inject({ url: "/v1/music/tracks", headers })).statusCode).toBe(403);
    const ok = await app.inject({ url: "/v1/music/tracks?tier=pro", headers });
    expect(ok.statusCode).toBe(200);
    expect(ok.json().tracks[0].attribution).toBe("A – Morning Mist");

    const cues = [{ at_card: 0, mood: "calm", energy: 1, description: "soft" }];
    expect((await app.inject({ method: "POST", url: "/v1/music/plan", headers, payload: { tier: "free", cues } })).statusCode).toBe(403);
    const plan = await app.inject({ method: "POST", url: "/v1/music/plan", headers, payload: { tier: "plus", cues } });
    expect(plan.json()).toEqual({ picks: [{ at_card: 0, track_id: "t1" }], source: "rules" });
  });
});
