import { existsSync, readFileSync } from "node:fs";

import { z } from "zod";

import { MOODS } from "../config.js";

/**
 * Soundtrack catalog (paid tiers). Tracks are listed in a JSON file you
 * control (MUSIC_CATALOG, default ./music/catalog.json). Every track must
 * carry its license and the attribution text shown in the app.
 *
 * Licensing: NoCopyrightSounds (NCS) allows free use in online videos and
 * streams, but use inside an app or a paid feature needs a license from NCS.
 * Only add tracks you have the rights to stream in the app.
 */
export const TrackSchema = z.object({
  id: z.string().min(1).max(80),
  title: z.string().min(1).max(200),
  artist: z.string().min(1).max(200),
  url: z.string().url().refine((u) => u.startsWith("https://"), "track URLs must use https"),
  moods: z.array(z.enum(MOODS)).min(1),
  energy: z.number().int().min(1).max(5),
  bpm: z.number().int().positive().optional(),
  duration_s: z.number().int().positive().optional(),
  license: z.string().min(3).max(300),
  attribution: z.string().min(3).max(300),
  source_url: z.string().url().optional(),
});
export type Track = z.infer<typeof TrackSchema>;

export interface CatalogLoad {
  tracks: Track[];
  errors: string[];
}

/** Loads and validates the catalog; invalid entries are skipped and reported. */
export function loadCatalog(path: string): CatalogLoad {
  if (!existsSync(path)) return { tracks: [], errors: [] };
  let json: unknown;
  try {
    json = JSON.parse(readFileSync(path, "utf8"));
  } catch (e) {
    return { tracks: [], errors: [`${path}: invalid JSON (${(e as Error).message})`] };
  }
  const list = (json as { tracks?: unknown })?.tracks;
  if (!Array.isArray(list)) return { tracks: [], errors: [`${path}: expected {"tracks": [...]}`] };
  const tracks: Track[] = [];
  const errors: string[] = [];
  const ids = new Set<string>();
  list.forEach((entry, i) => {
    const parsed = TrackSchema.safeParse(entry);
    if (!parsed.success) {
      errors.push(`track #${i + 1}: ${parsed.error.issues.map((x) => `${x.path.join(".")}: ${x.message}`).join("; ")}`);
      return;
    }
    if (ids.has(parsed.data.id)) {
      errors.push(`track #${i + 1}: duplicate id ${parsed.data.id}`);
      return;
    }
    ids.add(parsed.data.id);
    tracks.push(parsed.data);
  });
  return { tracks, errors };
}
