import 'package:book_reel/core/habit/habit_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('evaluateDwell', () {
    test('verifies attentive reads and rejects skims', () {
      // 120 words at 240 wpm = 30 s expected; 35% = 10.5 s, and no faster than 500 wpm = 14.4 s.
      expect(evaluateDwell(words: 120, dwellMs: 15000, wpm: 240).verified, isTrue);
      expect(evaluateDwell(words: 120, dwellMs: 12000, wpm: 240).verified, isFalse, reason: '600 wpm is skimming');
      expect(evaluateDwell(words: 120, dwellMs: 5000, wpm: 240).verified, isFalse);
      expect(evaluateDwell(words: 120, dwellMs: 5000, wpm: 240).minutes, 0);
    });

    test('faster than careful reading is skimming, whatever the learnt speed; skims teach nothing', () {
      expect(evaluateDwell(words: 120, dwellMs: 12000, wpm: 500).verified, isFalse); // 600 wpm
      expect(evaluateDwell(words: 120, dwellMs: 15000, wpm: 500).verified, isTrue); // 480 wpm
      // A speed learnt above the ceiling (older versions allowed 600) is brought under it.
      expect(evaluateDwell(words: 120, dwellMs: 13000, wpm: 600).verified, isFalse);
      // Steady skimming at about 730 wpm used to teach the speed up; now it teaches nothing.
      var wpm = 400.0;
      for (var i = 0; i < 50; i++) {
        final r = evaluateDwell(words: 120, dwellMs: (0.55 * 120 / wpm * 60000).round(), wpm: wpm);
        expect(r.verified, isFalse);
        wpm = r.updatedWpm;
      }
      expect(wpm, 400);
    });

    test('a day keeps the words of the cards really read', () {
      var day = const DailyStat();
      day = day.add(verified: true, minutes: 0.5, words: 120);
      day = day.add(verified: false, minutes: 0, words: 300);
      expect((day.verifiedCards, day.skimmedCards, day.words), (1, 1, 120));
      expect(DailyStat.fromJson(day.toJson()).words, 120);
      expect(DailyStat.fromJson(const {'v': 3, 's': 0, 'm': 2.0}).words, 0, reason: 'days saved before words were kept');
    });

    test('caps credited minutes and learns WPM only from plausible reads', () {
      final idle = evaluateDwell(words: 120, dwellMs: 600000, wpm: 240);
      expect(idle.minutes, closeTo(1.5, 0.001)); // 3 × 30 s
      expect(idle.updatedWpm, 240);
      final fast = evaluateDwell(words: 120, dwellMs: 20000, wpm: 240); // 360 wpm observed
      expect(fast.updatedWpm, greaterThan(240));
      expect(fast.updatedWpm, lessThan(360));
    });
  });

  group('StreakEngine', () {
    const engine = StreakEngine(GoalConfig(freezesPerWeek: 1));
    final mon = DateTime(2026, 11, 2);
    DateTime day(int offset) => DateTime(mon.year, mon.month, mon.day + offset);

    test('counts consecutive days and ignores repeat calls on the same day', () {
      var s = const StreakState();
      s = engine.recordGoalMet(s, day(0));
      s = engine.recordGoalMet(s, day(0));
      s = engine.recordGoalMet(s, day(1));
      expect(s.current, 2);
      expect(s.best, 2);
    });

    test('uses a freeze for one missed day, restarts after more', () {
      var s = const StreakState();
      s = engine.recordGoalMet(s, day(0));
      s = engine.recordGoalMet(s, day(1));
      s = engine.recordGoalMet(s, day(3)); // missed day 2, freeze covers it
      expect(s.current, 3);
      expect(s.freezesLeft, 0);
      expect(s.frozenDates, ['2026-11-04']);
      s = engine.recordGoalMet(s, day(6)); // missed 2 days, no freezes left
      expect(s.current, 1);
      expect(s.best, 3);
    });

    test('freezes refill each week', () {
      var s = engine.recordGoalMet(const StreakState(), day(0));
      s = engine.recordGoalMet(s, day(2)); // uses this week's freeze
      expect(s.freezesLeft, 0);
      s = engine.recordGoalMet(s, day(8)); // next week: refilled, but 5 days missed
      expect(s.current, 1);
      s = engine.recordGoalMet(s, day(10)); // one missed day, refilled freeze covers it
      expect(s.current, 2);
    });

    test('display streak survives until missed days exceed freezes', () {
      final s = engine.recordGoalMet(const StreakState(), day(0));
      expect(engine.displayStreak(s, day(1)), 1);
      expect(engine.displayStreak(s, day(2)), 1); // one missed day, freeze available
      expect(engine.displayStreak(s, day(3)), 0);
    });

    test('weekly mode counts consecutive qualifying weeks', () {
      const weekly = StreakEngine(GoalConfig(mode: GoalMode.weekly, weeklyDays: 3, dailyTarget: 1));
      final stats = <String, DailyStat>{};
      for (final offset in [-7, -6, -5, 0, 1, 2]) {
        stats[dateKey(day(offset))] = const DailyStat(verifiedCards: 1);
      }
      expect(weekly.weeklyStreak(stats, day(3)), 2);
      stats.remove(dateKey(day(2)));
      expect(weekly.weeklyStreak(stats, day(3)), 1); // this week not yet met, last week counts
    });
  });

  test('date helpers', () {
    expect(dateKey(DateTime(2026, 1, 5)), '2026-01-05');
    expect(daysBetween('2026-03-28', '2026-03-30'), 2);
    expect(weekKey(DateTime(2026, 11, 8)), '2026-11-02'); // Sunday → Monday of that week
  });
}
