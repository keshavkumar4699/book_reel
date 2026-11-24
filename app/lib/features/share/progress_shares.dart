import '../../core/habit/habit_engine.dart';
import '../../core/models/book.dart';
import '../../data/habit.dart';
import '../../data/sessions.dart';
import '../../ui/kit.dart';
import 'share_sheet.dart';
import '../../l10n/l10n.dart';

/// What gets shared, Strava-style: every figure that counts. Only reading
/// that was really done is in them (skimmed reels count toward nothing).

/// 950, 1.2k, 12k, 1.3M: a count that fits a small figure.
String compactCount(int n) {
  String one(double v) => v.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
  if (n < 1000) return '$n';
  if (n < 10000) return '${one(n / 1000)}k';
  if (n < 1000000) return '${(n / 1000).round()}k';
  return '${one(n / 1000000)}M';
}

/// Today's goal met (or a streak milestone): today's cards, words and
/// time, the streak, the reading pace and how far into the book.
ProgressShare goalShare({
  required HabitState habit,
  required int streak,
  int? milestone,
  required String bookTitle,
  required double bookProgress,
  required DateTime now,
}) {
  final today = habit.today(now);
  return ProgressShare(
    emoji: '🔥',
    headline: milestone != null ? tr('{n}-day reading streak!', {'n': milestone}) : tr('Today’s reading goal, done'),
    subtitle: tr('Reading {title}', {'title': bookTitle}),
    stats: [
      ('${today.verifiedCards}', trn(today.verifiedCards, 'card', 'cards'), KitHue.activity),
      (compactCount(today.words), tr('words'), KitHue.pages),
      (shareDuration(today.minutes), tr('time'), KitHue.time),
      ('$streak', tr('day streak'), KitHue.growth),
      ('${habit.wpm.round()}', tr('words/min'), KitHue.pages),
      ('${(bookProgress * 100).clamp(0, 100).round()}%', tr('of the book'), KitHue.books),
    ],
  );
}

/// A book finished: the words read in it, its cards, time and days (from
/// the reading sessions kept on the phone), the streak and books so far.
ProgressShare bookShare({
  required BookMeta book,
  required List<ReadingSession> sessions,
  required int streak,
  required int booksFinished,
}) {
  final mine = [for (final s in sessions) if (s.bookId == book.id) s];
  final minutes = mine.fold(0.0, (n, s) => n + s.minutes);
  final cards = mine.fold(0, (n, s) => n + s.cards);
  final days = {for (final s in mine) dateKey(s.startedAt)}.length;
  return ProgressShare(
    emoji: '🎉',
    headline: tr('Finished {title}', {'title': book.title}),
    subtitle: tr('by {author}', {'author': book.author}),
    book: book,
    stats: [
      (compactCount(book.wordsRead ?? 0), tr('words read'), KitHue.pages),
      ('$cards', trn(cards, 'card', 'cards'), KitHue.activity),
      (shareDuration(minutes), tr('time'), KitHue.time),
      ('$days', trn(days, 'day', 'days'), KitHue.growth),
      ('$streak', tr('day streak'), KitHue.growth),
      ('$booksFinished', trn(booksFinished, 'book read', 'books read'), KitHue.books),
    ],
  );
}

/// The profile: all-time books, cards, words, time and streaks.
ProgressShare profileShare({
  required String name,
  String? handle,
  String emoji = '📖',
  String? reading,
  required HabitState habit,
  required int streak,
  required int booksFinished,
}) =>
    ProgressShare(
      emoji: emoji,
      headline: handle == null || handle.isEmpty ? tr('{name} on Cloro', {'name': name}) : '$name · @$handle',
      subtitle: reading == null ? null : tr('Reading {title}', {'title': reading}),
      stats: [
        ('$booksFinished', trn(booksFinished, 'book read', 'books read'), KitHue.books),
        (compactCount(habit.totalVerifiedCards), tr('cards'), KitHue.activity),
        (compactCount(habit.totalWords), tr('words read'), KitHue.pages),
        (shareDuration(habit.totalMinutes), tr('time'), KitHue.time),
        ('$streak', tr('day streak'), KitHue.growth),
        ('${habit.streak.best}', tr('best streak'), KitHue.growth),
      ],
    );

/// Words on a printed page, for pages read (a paperback holds about this many).
const wordsPerPage = 275;

/// Pages for [words] read: at least one once anything was.
int pagesFor(int words) => words <= 0 ? 0 : (words / wordsPerPage).round().clamp(1, 1 << 30);

/// What a progress card from the Journal covers.
enum SharePeriod { today, week, all }

/// Your reading at any moment, from the Journal: the book you're reading and
/// the page you're on, then for [period] the time, pages and cards read, the
/// streak, and how far into the book (or, all time, the books read). Only
/// reading really done counts (skimmed reels count toward nothing).
ProgressShare journalShare({
  required SharePeriod period,
  required HabitState habit,
  required int streak,
  bool weekly = false,
  required BookMeta? reading,
  required int booksFinished,
  required DateTime now,
}) {
  final days = switch (period) {
    SharePeriod.today => [habit.today(now)],
    // Today and the six days before it, as the Profile's week.
    SharePeriod.week => [
        for (var i = 0; i < 7; i++) habit.stats[dateKey(DateTime(now.year, now.month, now.day - i))] ?? const DailyStat(),
      ],
    SharePeriod.all => habit.stats.values.toList(),
  };
  final minutes = days.fold(0.0, (n, d) => n + d.minutes);
  final cards = days.fold(0, (n, d) => n + d.verifiedCards);
  final pages = pagesFor(days.fold(0, (n, d) => n + d.words));
  final daysRead = days.where((d) => d.minutes > 0 || d.verifiedCards > 0).length;
  final ShareStat streakStat = ('$streak', weekly ? tr('week streak') : tr('day streak'), KitHue.growth);
  final book = reading;
  String? where;
  if (book != null) {
    final total = pagesFor(book.wordCount);
    final page = (book.progress.clamp(0.0, 1.0) * total).round().clamp(1, total < 1 ? 1 : total);
    where = total > 1
        ? tr('Reading {title} · page {page} of {pages}', {'title': book.title, 'page': page, 'pages': total})
        : tr('Reading {title}', {'title': book.title});
  }
  final ShareStat? inBook = book == null ? null : ('${(book.progress * 100).clamp(0, 100).round()}%', tr('of the book'), KitHue.books);
  return ProgressShare(
    emoji: switch (period) { SharePeriod.today => '📖', SharePeriod.week => '🗓️', SharePeriod.all => '📚' },
    headline: switch (period) {
      SharePeriod.today => tr('Today’s reading'),
      SharePeriod.week => tr('My week of reading'),
      SharePeriod.all => tr('My reading so far'),
    },
    subtitle: where,
    book: book,
    stats: [
      (shareDuration(minutes), tr('time'), KitHue.time),
      (compactCount(pages), trn(pages, 'page', 'pages'), KitHue.pages),
      (compactCount(cards), trn(cards, 'card', 'cards'), KitHue.activity),
      streakStat,
      ...switch (period) {
        SharePeriod.today => [
            ('${habit.wpm.round()}', tr('words/min'), KitHue.pages),
            inBook ?? ('$booksFinished', trn(booksFinished, 'book read', 'books read'), KitHue.books),
          ],
        SharePeriod.week => [
            ('$daysRead/7', tr('days read'), KitHue.growth),
            inBook ?? ('$booksFinished', trn(booksFinished, 'book read', 'books read'), KitHue.books),
          ],
        SharePeriod.all => [
            ('${habit.streak.best}', tr('best streak'), KitHue.growth),
            ('$booksFinished', trn(booksFinished, 'book read', 'books read'), KitHue.books),
          ],
      },
    ],
  );
}
