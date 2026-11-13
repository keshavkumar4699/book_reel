import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { buildApp } from "../src/app.js";
import type { Db } from "../src/db/db.js";
import { markdownToHtml, readLegal } from "../src/legal.js";
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

describe("privacy policy and terms", () => {
  it("are served as pages from the app's own copy", async () => {
    const a = app();
    const privacy = await a.inject({ url: "/privacy" });
    expect(privacy.statusCode).toBe(200);
    expect(privacy.headers["content-type"]).toContain("text/html");
    expect(privacy.body).toContain("<h1>Privacy policy</h1>");
    expect(privacy.body).toContain("<h2>What we keep when online features are on</h2>");
    expect(privacy.body).toContain("<th>Service</th>");
    expect(privacy.body).toContain("Download my data");
    const terms = await a.inject({ url: "/terms" });
    expect(terms.body).toContain("<h1>Terms of use</h1>");
    expect(readLegal("terms")).toContain("## Be kind");
  });

  it("render the Markdown they use, escaped", () => {
    const html = markdownToHtml(
      "# Title\n\nA **bold** <script>x</script> line\ncontinued.\n\n- one\n- two\n\n| A | B |\n|---|---|\n| 1 | 2 |\n",
    );
    expect(html).toBe(
      [
        "<h1>Title</h1>",
        "<p>A <strong>bold</strong> &lt;script&gt;x&lt;/script&gt; line continued.</p>",
        "<ul><li>one</li><li>two</li></ul>",
        "<table><thead><tr><th>A</th><th>B</th></tr></thead><tbody><tr><td>1</td><td>2</td></tr></tbody></table>",
      ].join("\n"),
    );
  });
});
