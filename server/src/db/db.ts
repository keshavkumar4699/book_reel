import { mkdirSync } from "node:fs";

import { PGlite } from "@electric-sql/pglite";
import pg from "pg";

import { MIGRATIONS } from "./migrations.js";

/**
 * Minimal database interface shared by node-postgres (production) and PGlite
 * (embedded Postgres for local development and tests). Same SQL either way.
 */
export interface Db {
  query<T = Record<string, unknown>>(sql: string, params?: unknown[]): Promise<T[]>;
  exec(sql: string): Promise<void>;
  close(): Promise<void>;
}

/**
 * `postgres://…` → node-postgres pool. Anything else is a PGlite data
 * directory; empty/undefined → in-memory PGlite.
 */
export async function openDb(url?: string): Promise<Db> {
  let db: Db;
  if (url && /^postgres(ql)?:\/\//.test(url)) {
    const pool = new pg.Pool({ connectionString: url, max: 10 });
    db = {
      query: async <T>(sql: string, params: unknown[] = []) => (await pool.query(sql, params)).rows as T[],
      exec: async (sql: string) => {
        await pool.query(sql);
      },
      close: () => pool.end(),
    };
  } else {
    if (url && !url.startsWith("memory://")) mkdirSync(url, { recursive: true });
    const lite = new PGlite(url || undefined);
    db = {
      query: async <T>(sql: string, params: unknown[] = []) => (await lite.query<T>(sql, params)).rows,
      exec: async (sql: string) => {
        await lite.exec(sql);
      },
      close: () => lite.close(),
    };
  }
  await migrate(db);
  return db;
}

export async function migrate(db: Db): Promise<void> {
  await db.exec(
    "create table if not exists schema_migrations (version int primary key, applied_at timestamptz not null default now())",
  );
  const done = new Set((await db.query<{ version: number }>("select version from schema_migrations")).map((r) => r.version));
  for (const [i, sql] of MIGRATIONS.entries()) {
    const version = i + 1;
    if (done.has(version)) continue;
    await db.exec(`begin; ${sql}; insert into schema_migrations (version) values (${version}); commit;`);
  }
}
