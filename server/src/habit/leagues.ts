import type { Db } from "../db/db.js";
import type { ActivityService } from "./activity.js";

/**
 * Weekly leagues (UX_DESIGN.md §5.7): groups of up to 24 readers in the same
 * division, ranked by consistency (goal days) then verified minutes. Top 5
 * move up and bottom 5 move down when the week closes. Readers flagged by
 * anomaly detection are not placed.
 */
export const DIVISIONS = ["Bronze", "Silver", "Gold", "Sapphire", "Ruby", "Diamond"] as const;
export const LEAGUE_SIZE = 24;
export const PROMOTE = 5;
export const DEMOTE = 5;

export class LeagueService {
  constructor(
    private readonly db: Db,
    private readonly activity: ActivityService,
  ) {}

  async divisionOf(userId: string): Promise<number> {
    const rows = await this.db.query<{ division: number }>("select division from league_divisions where user_id = $1", [userId]);
    return rows[0]?.division ?? 0;
  }

  /** Places a user into an open group of their division for [week]; returns the group id. */
  async join(userId: string, week: string): Promise<string | undefined> {
    const u = await this.activity.user(userId);
    if (u.hidden) return undefined;
    const existing = await this.db.query<{ group_id: string }>(
      "select group_id from league_members where week = $1 and user_id = $2",
      [week, userId],
    );
    if (existing[0]) return existing[0].group_id;
    const div = await this.divisionOf(userId);
    let group = (
      await this.db.query<{ id: string }>(
        "select id from league_groups where week = $1 and division = $2 and members < $3 order by id limit 1",
        [week, div, LEAGUE_SIZE],
      )
    )[0]?.id;
    if (!group) {
      const n = (await this.db.query<{ n: string | number }>("select count(*) as n from league_groups where week = $1 and division = $2", [week, div]))[0]!.n;
      group = `${week}-${div}-${n}`;
      await this.db.query("insert into league_groups (id, week, division) values ($1, $2, $3) on conflict do nothing", [group, week, div]);
    }
    const inserted = await this.db.query(
      "insert into league_members (week, user_id, group_id) values ($1, $2, $3) on conflict do nothing returning 1",
      [week, userId, group],
    );
    if (inserted.length) await this.db.query("update league_groups set members = members + 1 where id = $1", [group]);
    return group;
  }

  async standings(userId: string, week: string) {
    const groupId = await this.join(userId, week);
    if (!groupId) return undefined;
    const group = (await this.db.query<{ division: number }>("select division from league_groups where id = $1", [groupId]))[0]!;
    const members = (await this.db.query<{ user_id: string }>("select user_id from league_members where group_id = $1", [groupId])).map(
      (r) => r.user_id,
    );
    const [scores, names] = await Promise.all([this.activity.weekScores(members, week), this.activity.names(members)]);
    const rows = members
      .map((id) => ({ userId: id, name: names.get(id) ?? "Reader", me: id === userId, ...scores.get(id)! }))
      .sort((a, b) => b.score - a.score)
      .map((r, i) => ({ ...r, rank: i + 1 }));
    return { division: DIVISIONS[group.division], groupId, rows, promote: PROMOTE, demote: DEMOTE, size: LEAGUE_SIZE };
  }

  /** Applies promotions/demotions for [week]. Only readers with activity can move up. */
  async closeWeek(week: string): Promise<{ promoted: string[]; demoted: string[] }> {
    const promoted: string[] = [];
    const demoted: string[] = [];
    const groups = await this.db.query<{ id: string; division: number }>("select id, division from league_groups where week = $1", [week]);
    for (const g of groups) {
      const members = (await this.db.query<{ user_id: string }>("select user_id from league_members where group_id = $1", [g.id])).map(
        (r) => r.user_id,
      );
      const scores = await this.activity.weekScores(members, week);
      const ranked = members.map((id) => ({ id, score: scores.get(id)!.score })).sort((a, b) => b.score - a.score);
      for (const r of ranked.slice(0, PROMOTE)) {
        if (r.score > 0 && g.division < DIVISIONS.length - 1) {
          await this.setDivision(r.id, g.division + 1);
          promoted.push(r.id);
        }
      }
      if (ranked.length >= PROMOTE + DEMOTE) {
        for (const r of ranked.slice(-DEMOTE)) {
          if (g.division > 0 && !promoted.includes(r.id)) {
            await this.setDivision(r.id, g.division - 1);
            demoted.push(r.id);
          }
        }
      }
    }
    return { promoted, demoted };
  }

  private async setDivision(userId: string, division: number) {
    await this.db.query(
      "insert into league_divisions (user_id, division) values ($1, $2) on conflict (user_id) do update set division = excluded.division",
      [userId, division],
    );
  }
}
