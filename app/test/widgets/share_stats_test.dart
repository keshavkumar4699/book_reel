import 'package:book_reel/core/habit/habit_engine.dart';
import 'package:book_reel/core/models/book.dart';
import 'package:book_reel/data/habit.dart';
import 'package:book_reel/data/sessions.dart';
import 'package:book_reel/features/share/progress_shares.dart';
import 'package:book_reel/features/share/share_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 17, 21);
  final habit = HabitState(
    stats: {
      dateKey(now): const DailyStat(verifiedCards: 24, skimmedCards: 9, minutes: 18.4, words: 3120),
      dateKey(DateTime(2026, 11, 16)): const DailyStat(verifiedCards: 30, minutes: 25, words: 4100),
    },
    streak: const StreakState(current: 12, best: 20),
    wpm: 248,
    booksFinished: 3,
  );

  test('counts read at a glance', () {
    expect([for (final n in [950, 1200, 1000, 9950, 12400, 999999, 1300000]) compactCount(n)],
        ['950', '1.2k', '1k', '9.9k', '12k', '1000k', '1.3M']);
  });

  test('goal done: today’s cards, words and time, the streak, pace and the book; skimmed reels left out', () {
    final share = goalShare(habit: habit, streak: 12, bookTitle: 'Emma', bookProgress: 0.34, now: now);
    expect(share.headline, 'Today’s reading goal, done');
    expect(share.subtitle, 'Reading Emma');
    expect(share.stats, [
      ('24', 'cards'),
      ('3.1k', 'words'),
      ('18 min', 'time'),
      ('12', 'day streak'),
      ('248', 'words/min'),
      ('34%', 'of the book'),
    ]);
    expect(goalShare(habit: habit, streak: 30, milestone: 30, bookTitle: 'Emma', bookProgress: 0, now: now).headline, '30-day reading streak!');
  });

  test('a finished book: its words, cards, time and days, the streak and books so far', () {
    final book = BookMeta(
      id: 'b1', title: 'Emma', author: 'Jane Austen', format: BookFormat.epub, addedAt: now, wordCount: 160000, chapterCount: 55, wordsRead: 131200);
    ReadingSession s(String book, DateTime at, double minutes, int cards) =>
        ReadingSession(id: '$at', bookId: book, title: 'Emma', author: 'Jane Austen', startedAt: at, endedAt: at, minutes: minutes, cards: cards);
    final share = bookShare(
      book: book,
      sessions: [s('b1', DateTime(2026, 11, 1, 9), 40, 30), s('b1', DateTime(2026, 11, 1, 21), 25, 20), s('b2', DateTime(2026, 11, 2), 99, 99), s('b1', DateTime(2026, 11, 3), 70, 51)],
      streak: 12,
      booksFinished: 4,
    );
    expect(share.headline, 'Finished Emma');
    expect(share.stats, [
      ('131k', 'words read'),
      ('101', 'cards'),
      ('2 h 15 min', 'time'),
      ('2', 'days'),
      ('12', 'day streak'),
      ('4', 'books read'),
    ]);
  });

  test('the profile: all-time figures', () {
    final share = profileShare(name: 'Asha', handle: 'asha.reads', reading: 'Emma', habit: habit, streak: 12, booksFinished: 3);
    expect(share.headline, 'Asha · @asha.reads');
    expect(share.stats, [
      ('3', 'books read'),
      ('54', 'cards'),
      ('7.2k', 'words read'),
      ('43 min', 'time'),
      ('12', 'day streak'),
      ('20', 'best streak'),
    ]);
    expect(share.statsLine, '3 books read · 54 cards · 7.2k words read · 43 min · 12 day streak · 20 best streak');
  });

  testWidgets('the card shows every figure, in a grid, on both shapes', (tester) async {
    final share = goalShare(habit: habit, streak: 12, bookTitle: 'Emma', bookProgress: 0.34, now: now);
    for (final aspect in ShareAspect.values) {
      await tester.pumpWidget(MaterialApp(
        home: Center(child: ShareCardArt(content: share, template: ShareTemplate.dark, aspect: aspect)),
      ));
      for (final (value, label) in share.stats) {
        expect(find.text(value), findsOneWidget, reason: '$label on ${aspect.name}');
        expect(find.text(label.toUpperCase()), findsOneWidget);
      }
      expect(tester.takeException(), isNull, reason: 'nothing overflows on ${aspect.name}');
      // Three figures to a row.
      expect(tester.getTopLeft(find.text('24')).dy, tester.getTopLeft(find.text('18 min')).dy);
      expect(tester.getTopLeft(find.text('12')).dy, greaterThan(tester.getTopLeft(find.text('24')).dy));
    }
  });
}
