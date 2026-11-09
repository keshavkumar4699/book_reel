/// Reading verification, goals and streaks (DESIGN.md §2.9, UX_DESIGN.md §7).
/// Pure logic so it is unit-tested and mirrored by the server.
library;

import 'dart:math' as math;

const defaultWpm = 230.0;
const minWpm = 120.0;
const maxWpm = 600.0;

/// Minimum share of the expected reading time a card must stay on screen to
/// count as read.
const verifyRatio = 0.35;

class DwellResult {
  const DwellResult({required this.verified, required this.minutes, required this.updatedWpm});

  final bool verified;

  /// Credited reading minutes (capped at 3× expected time so idle screens
  /// don't inflate stats).
  final double minutes;
  final double updatedWpm;
}

DwellResult evaluateDwell({required int words, required int dwellMs, required double wpm}) {
  if (words <= 0) return DwellResult(verified: false, minutes: 0, updatedWpm: wpm);
  final expectedMs = words / wpm * 60000;
  final verified = dwellMs >= verifyRatio * expectedMs;
  final creditedMs = math.min(dwellMs.toDouble(), expectedMs * 3);
  var newWpm = wpm;
  // Learn reading speed only from plausible, attentive reads.
  if (dwellMs >= 0.5 * expectedMs && dwellMs <= 3 * expectedMs) {
    final observed = words / (dwellMs / 60000);
    newWpm = (0.85 * wpm + 0.15 * observed).clamp(minWpm, maxWpm).toDouble();
  }
  return DwellResult(verified: verified, minutes: verified ? creditedMs / 60000 : 0, updatedWpm: newWpm);
}

/// Local calendar date key: `yyyy-mm-dd`.
String dateKey(DateTime local) =>
    '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';

DateTime parseDateKey(String key) {
  final p = key.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

int daysBetween(String fromKey, String toKey) =>
    parseDateKey(toKey).difference(parseDateKey(fromKey)).inHours.round() ~/ 24;

/// Monday of the ISO week containing [day], as a date key.
String weekKey(DateTime day) => dateKey(DateTime(day.year, day.month, day.day - (day.weekday - 1)));

enum GoalUnit { cards, minutes }

enum GoalMode { daily, weekly }

class GoalConfig {
  const GoalConfig({
    this.unit = GoalUnit.cards,
    this.dailyTarget = 10,
    this.mode = GoalMode.daily,
    this.weeklyDays = 5,
    this.freezesPerWeek = 1,
  });

  final GoalUnit unit;
  final int dailyTarget;
  final GoalMode mode;
  final int weeklyDays;
  final int freezesPerWeek;
}

class DailyStat {
  const DailyStat({this.verifiedCards = 0, this.skimmedCards = 0, this.minutes = 0});

  final int verifiedCards;
  final int skimmedCards;
  final double minutes;

  DailyStat add({required bool verified, required double minutes}) => DailyStat(
        verifiedCards: verifiedCards + (verified ? 1 : 0),
        skimmedCards: skimmedCards + (verified ? 0 : 1),
        minutes: this.minutes + minutes,
      );

  bool meets(GoalConfig goal) =>
      goal.unit == GoalUnit.cards ? verifiedCards >= goal.dailyTarget : minutes >= goal.dailyTarget;

  double progress(GoalConfig goal) {
    final value = goal.unit == GoalUnit.cards ? verifiedCards.toDouble() : minutes;
    return (value / goal.dailyTarget).clamp(0, 1).toDouble();
  }

  Map<String, dynamic> toJson() => {'v': verifiedCards, 's': skimmedCards, 'm': minutes};

  factory DailyStat.fromJson(Map<String, dynamic> json) => DailyStat(
        verifiedCards: (json['v'] as num?)?.toInt() ?? 0,
        skimmedCards: (json['s'] as num?)?.toInt() ?? 0,
        minutes: ((json['m'] as num?) ?? 0).toDouble(),
      );
}

class StreakState {
  const StreakState({
    this.current = 0,
    this.best = 0,
    this.lastGoalDate,
    this.freezesLeft = 1,
    this.freezeWeek,
    this.frozenDates = const [],
  });

  final int current;
  final int best;
  final String? lastGoalDate;
  final int freezesLeft;
  final String? freezeWeek;
  final List<String> frozenDates;

  StreakState copyWith({
    int? current,
    int? best,
    String? lastGoalDate,
    int? freezesLeft,
    String? freezeWeek,
    List<String>? frozenDates,
  }) =>
      StreakState(
        current: current ?? this.current,
        best: best ?? this.best,
        lastGoalDate: lastGoalDate ?? this.lastGoalDate,
        freezesLeft: freezesLeft ?? this.freezesLeft,
        freezeWeek: freezeWeek ?? this.freezeWeek,
        frozenDates: frozenDates ?? this.frozenDates,
      );

  Map<String, dynamic> toJson() => {
        'current': current,
        'best': best,
        'last': lastGoalDate,
        'freezes': freezesLeft,
        'freezeWeek': freezeWeek,
        'frozen': frozenDates,
      };

  factory StreakState.fromJson(Map<String, dynamic> json) => StreakState(
        current: (json['current'] as int?) ?? 0,
        best: (json['best'] as int?) ?? 0,
        lastGoalDate: json['last'] as String?,
        freezesLeft: (json['freezes'] as int?) ?? 1,
        freezeWeek: json['freezeWeek'] as String?,
        frozenDates: ((json['frozen'] as List?) ?? const []).cast<String>(),
      );
}

class StreakEngine {
  const StreakEngine(this.goal);

  final GoalConfig goal;

  /// Refills freezes at the start of each ISO week.
  StreakState refill(StreakState s, DateTime today) {
    final wk = weekKey(today);
    if (s.freezeWeek == wk) return s;
    return s.copyWith(freezesLeft: goal.freezesPerWeek, freezeWeek: wk);
  }

  /// Call when the daily goal is met on [today]. Missed days in between are
  /// covered by freezes when enough are left; otherwise the streak restarts.
  StreakState recordGoalMet(StreakState state, DateTime today) {
    var s = refill(state, today);
    final key = dateKey(today);
    if (s.lastGoalDate == key) return s;
    if (s.lastGoalDate == null) {
      return s.copyWith(current: 1, best: math.max(1, s.best), lastGoalDate: key);
    }
    final missed = daysBetween(s.lastGoalDate!, key) - 1;
    if (missed < 0) return s; // clock moved backwards; ignore
    int current;
    var frozen = s.frozenDates;
    var freezes = s.freezesLeft;
    if (missed == 0) {
      current = s.current + 1;
    } else if (missed <= freezes) {
      final last = parseDateKey(s.lastGoalDate!);
      frozen = [
        ...s.frozenDates,
        for (var d = 1; d <= missed; d++) dateKey(DateTime(last.year, last.month, last.day + d)),
      ];
      freezes -= missed;
      current = s.current + 1;
    } else {
      current = 1;
    }
    return s.copyWith(
      current: current,
      best: math.max(s.best, current),
      lastGoalDate: key,
      freezesLeft: freezes,
      frozenDates: frozen.length > 60 ? frozen.sublist(frozen.length - 60) : frozen,
    );
  }

  /// Streak to display today: still alive if today or yesterday met the goal,
  /// or if the missed days can still be covered by freezes.
  int displayStreak(StreakState state, DateTime today) {
    if (state.lastGoalDate == null) return 0;
    final s = refill(state, today);
    final missed = daysBetween(s.lastGoalDate!, dateKey(today)) - 1;
    if (missed <= 0) return s.current;
    return missed <= s.freezesLeft ? s.current : 0;
  }

  /// Weekly mode: consecutive weeks (ending this week if already met, else
  /// last week) with at least [GoalConfig.weeklyDays] goal-met days.
  int weeklyStreak(Map<String, DailyStat> stats, DateTime today) {
    int metDays(String weekStart) {
      final start = parseDateKey(weekStart);
      var n = 0;
      for (var d = 0; d < 7; d++) {
        final stat = stats[dateKey(DateTime(start.year, start.month, start.day + d))];
        if (stat != null && stat.meets(goal)) n++;
      }
      return n;
    }

    var week = parseDateKey(weekKey(today));
    var streak = 0;
    if (metDays(dateKey(week)) >= goal.weeklyDays) streak++;
    week = DateTime(week.year, week.month, week.day - 7);
    while (metDays(dateKey(week)) >= goal.weeklyDays) {
      streak++;
      week = DateTime(week.year, week.month, week.day - 7);
    }
    return streak;
  }
}

/// Milestones that earn a celebration (rare on purpose: UX_DESIGN.md §6.4).
const streakMilestones = [3, 7, 14, 30, 50, 100, 200, 365];
