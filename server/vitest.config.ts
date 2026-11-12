import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    include: ["test/**/*.test.ts"],
    exclude: ["dist/**", "node_modules/**"],
    // Each test opens a fresh in-process Postgres (PGlite, WASM) and runs
    // every migration; on shared CI runners with test files in parallel that
    // takes 3–5 s, too close to vitest's 5 s default (a reopen test timed
    // out at 5.04 s).
    testTimeout: 30_000,
    hookTimeout: 30_000,
  },
});
