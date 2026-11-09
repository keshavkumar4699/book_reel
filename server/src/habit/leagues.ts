import type { ActivityService } from "./activity.js";

/**
 * Weekly leagues (UX_DESIGN.md §5.7): groups of up to 24 readers in the same
 * division, ranked by consistency (goal days) then verified minutes. Top 5
 * move up and bottom 5 move down when the week closes. Users who hide
 * comparisons or are flagged by anomaly detection are not placed.
 */
export const DIVISIONS = ["Bronze", "Silver", "Gold", "Sapphire", "Ruby", "Diamond"] as const;
export const LEAGUE_SIZE = 24;
export const PROMOTE = 5;
export const DEMOTE = 5;

interface Group {
  id: string;
  week: string;
  division: number;
  members: string[];
}

export class LeagueService {
  private readonly division = new Map<string, number>();
  private readonly groups = new Map<string, Group[]>(); // week -> groups
  private readonly membership = new Map<string, string>(); // `${week}|${user}` -> group id

  constructor(private readonly activity: ActivityService) {}

  divisionOf(userId: string): number {
    return this.division.get(userId) ?? 0;
  }

  /** Places a user into an open group of their division for [week]. */
  join(userId: string, week: string): Group | undefined {
    if (this.activity.user(userId).hidden) return undefined;
    const existing = this.membership.get(`${week}|${userId}`);
    const weekGroups = this.groups.get(week) ?? [];
    if (existing) return weekGroups.find((g) => g.id === existing);
    const div = this.divisionOf(userId);
    let group = weekGroups.find((g) => g.division === div && g.members.length < LEAGUE_SIZE);
    if (!group) {
      group = { id: `${week}-${div}-${weekGroups.filter((g) => g.division === div).length}`, week, division: div, members: [] };
      weekGroups.push(group);
      this.groups.set(week, weekGroups);
    }
    group.members.push(userId);
    this.membership.set(`${week}|${userId}`, group.id);
    return group;
  }

  standings(userId: string, week: string) {
    const group = this.join(userId, week);
    if (!group) return undefined;
    const rows = group.members
      .map((id) => ({ userId: id, name: this.activity.user(id).displayName, ...this.activity.weekScore(id, week) }))
      .sort((a, b) => b.score - a.score)
      .map((r, i) => ({ ...r, rank: i + 1 }));
    return { division: DIVISIONS[group.division], groupId: group.id, rows, promote: PROMOTE, demote: DEMOTE };
  }

  /** Applies promotions/demotions for [week]. Only readers with activity can move up. */
  closeWeek(week: string): { promoted: string[]; demoted: string[] } {
    const promoted: string[] = [];
    const demoted: string[] = [];
    for (const g of this.groups.get(week) ?? []) {
      const ranked = g.members
        .map((id) => ({ id, score: this.activity.weekScore(id, week).score }))
        .sort((a, b) => b.score - a.score);
      ranked.slice(0, PROMOTE).forEach((r) => {
        if (r.score > 0 && g.division < DIVISIONS.length - 1) {
          this.division.set(r.id, g.division + 1);
          promoted.push(r.id);
        }
      });
      if (ranked.length >= PROMOTE + DEMOTE) {
        ranked.slice(-DEMOTE).forEach((r) => {
          if (g.division > 0 && !promoted.includes(r.id)) {
            this.division.set(r.id, g.division - 1);
            demoted.push(r.id);
          }
        });
      }
    }
    return { promoted, demoted };
  }
}
