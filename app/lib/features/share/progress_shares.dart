import '../../core/habit/habit_engine.dart';
import '../../core/models/book.dart';
import '../../data/habit.dart';
import '../../data/sessions.dart';
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
      ('${today.verifiedCards}', trn(today.verifiedCards, 'card', 'cards')),
      (compactCount(today.words), tr('words')),
      (shareDuration(today.minutes), tr('time')),
      ('$streak', tr('day streak')),
      ('${habit.wpm.round()}', tr('words/min')),
      ('${(bookProgress * 100).clamp(0, 100).round()}%', tr('of the book')),
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
    stats: [
      (compactCount(book.wordsRead ?? 0), tr('words read')),
      ('$cards', trn(cards, 'card', 'cards')),
      (shareDuration(minutes), 'time'),
      ('$days', trn(days, 'day', 'days')),
      ('$streak', tr('day streak')),
      ('$booksFinished', trn(booksFinished, 'book read', 'books read')),
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
        ('$booksFinished', trn(booksFinished, 'book read', 'books read')),
        (compactCount(habit.totalVerifiedCards), tr('cards')),
        (compactCount(habit.totalWords), tr('words read')),
        (shareDuration(habit.totalMinutes), tr('time')),
        ('$streak', tr('day streak')),
        ('${habit.streak.best}', tr('best streak')),
      ],
    );
