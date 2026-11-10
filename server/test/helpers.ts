import { openDb, type Db } from "../src/db/db.js";

/** Fresh in-memory Postgres (PGlite) with migrations applied. */
export async function testDb(): Promise<Db> {
  return openDb();
}
