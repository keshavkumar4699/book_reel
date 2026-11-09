/**
 * Server mirror of app/lib/core/habit/habit_engine.dart. The server
 * re-verifies every reading event before it counts toward streaks or
 * leagues (DESIGN.md §2.9 "Fair play").
 */
export const DEFAULT_WPM = 230;
export const MIN_WPM = 120;
export const MAX_WPM = 600;
export const VERIFY_RATIO = 0.35;
/** Leaderboards count at most this many verified minutes per day. */
export const DAILY_MINUTES_CAP = 240;
/** Reading faster than this is implausible and flags the event. */
export const IMPLAUSIBLE_WPM = 1500;

export interface DwellResult {
  verified: boolean;
  minutes: number;
  updatedWpm: number;
  implausible: boolean;
}

export function evaluateDwell(words: number, dwellMs: number, wpm: number): DwellResult {
  if (words <= 0 || dwellMs <= 0) return { verified: false, minutes: 0, updatedWpm: wpm, implausible: false };
  const expectedMs = (words / wpm) * 60000;
  const observedWpm = words / (dwellMs / 60000);
  const implausible = observedWpm > IMPLAUSIBLE_WPM && dwellMs >= VERIFY_RATIO * expectedMs;
  const verified = dwellMs >= VERIFY_RATIO * expectedMs && !implausible;
  const creditedMs = Math.min(dwellMs, expectedMs * 3);
  let updatedWpm = wpm;
  if (dwellMs >= 0.5 * expectedMs && dwellMs <= 3 * expectedMs) {
    updatedWpm = Math.min(MAX_WPM, Math.max(MIN_WPM, 0.85 * wpm + 0.15 * observedWpm));
  }
  return { verified, minutes: verified ? creditedMs / 60000 : 0, updatedWpm, implausible };
}

export const dateKey = (d: Date): string => d.toISOString().slice(0, 10);

/** Local calendar date of an event given the client's UTC offset in minutes. */
export function localDateKey(ts: Date, tzOffsetMin: number): string {
  return dateKey(new Date(ts.getTime() + tzOffsetMin * 60000));
}

export function daysBetween(from: string, to: string): number {
  return Math.round((Date.parse(`${to}T00:00:00Z`) - Date.parse(`${from}T00:00:00Z`)) / 86400000);
}

export function addDays(key: string, n: number): string {
  return dateKey(new Date(Date.parse(`${key}T00:00:00Z`) + n * 86400000));
}

/** Monday of the ISO week containing [key]. */
export function weekKey(key: string): string {
  const d = new Date(`${key}T00:00:00Z`);
  const dow = (d.getUTCDay() + 6) % 7;
  return addDays(key, -dow);
}

export interface StreakState {
  current: number;
  best: number;
  lastGoalDate?: string;
  freezesLeft: number;
  freezeWeek?: string;
}

export const emptyStreak = (freezes: number): StreakState => ({ current: 0, best: 0, freezesLeft: freezes });

export function refill(s: StreakState, today: string, freezesPerWeek: number): StreakState {
  const wk = weekKey(today);
  return s.freezeWeek === wk ? s : { ...s, freezesLeft: freezesPerWeek, freezeWeek: wk };
}

export function recordGoalMet(state: StreakState, today: string, freezesPerWeek: number): StreakState {
  const s = refill(state, today, freezesPerWeek);
  if (s.lastGoalDate === today) return s;
  if (!s.lastGoalDate) return { ...s, current: 1, best: Math.max(1, s.best), lastGoalDate: today };
  const missed = daysBetween(s.lastGoalDate, today) - 1;
  if (missed < 0) return s;
  let current: number;
  let freezes = s.freezesLeft;
  if (missed === 0) current = s.current + 1;
  else if (missed <= freezes) {
    freezes -= missed;
    current = s.current + 1;
  } else current = 1;
  return { ...s, current, best: Math.max(s.best, current), lastGoalDate: today, freezesLeft: freezes };
}

export function displayStreak(state: StreakState, today: string, freezesPerWeek: number): number {
  if (!state.lastGoalDate) return 0;
  const s = refill(state, today, freezesPerWeek);
  const missed = daysBetween(s.lastGoalDate!, today) - 1;
  if (missed <= 0) return s.current;
  return missed <= s.freezesLeft ? s.current : 0;
}
