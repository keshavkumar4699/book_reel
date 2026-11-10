import { describe, expect, it } from "vitest";

import type { Track } from "../src/music/catalog.js";
import { MusicPicker, rulePicks, type TrackChooser } from "../src/music/picker.js";

const t = (id: string, moods: string[], energy: number, description?: string): Track =>
  ({ id, title: id, artist: "A", url: `https://x/${id}.mp3`, moods, energy, license: "lic", attribution: `A – ${id}`, description }) as Track;

const tracks = [t("calm-piano", ["calm"], 1, "soft piano"), t("lofi", ["calm", "reflective"], 2, "lo-fi beats"), t("pulse", ["tense"], 4, "pulsing synths"), t("anthem", ["epic"], 5)];
const cues = [
  { at_card: 0, mood: "calm" as const, energy: 2, description: "soft lo-fi" },
  { at_card: 9, mood: "tense" as const, energy: 4, description: "building tension" },
];

describe("music picks", () => {
  it("rule picks match mood and energy and avoid back-to-back repeats", () => {
    expect(rulePicks(cues, tracks)).toEqual([
      { at_card: 0, track_id: "lofi" },
      { at_card: 9, track_id: "pulse" },
    ]);
    const twoCalm = [cues[0]!, { ...cues[0]!, at_card: 5 }];
    const picks = rulePicks(twoCalm, tracks);
    expect(picks[0]!.track_id).not.toBe(picks[1]!.track_id);
  });

  it("uses the AI supervisor's choice, ignores unknown ids, and caches", async () => {
    let calls = 0;
    const chooser: TrackChooser = {
      choose: async () => {
        calls++;
        return [
          { cue: 0, track_id: "calm-piano" },
          { cue: 1, track_id: "not-in-catalog" },
        ];
      },
    };
    const picker = new MusicPicker(tracks, chooser);
    const req = { tier: "pro", cues };
    const res = await picker.plan(req);
    expect(res.source).toBe("ai");
    expect(res.picks).toEqual([
      { at_card: 0, track_id: "calm-piano" },
      { at_card: 9, track_id: "pulse" }, // unknown id replaced by the rule pick
    ]);
    await picker.plan(req);
    expect(calls).toBe(1);
  });

  it("falls back to rules when the AI fails, and returns nothing without a catalog", async () => {
    const failing = new MusicPicker(tracks, { choose: async () => { throw new Error("down"); } });
    expect((await failing.plan({ tier: "pro", cues })).source).toBe("rules");
    expect(await new MusicPicker([]).plan({ tier: "pro", cues })).toEqual({ picks: [], source: "none" });
  });
});
