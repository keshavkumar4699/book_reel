import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/habit/habit_engine.dart';
import '../../core/models/book.dart';
import '../../data/api_client.dart';
import '../../data/habit.dart';
import '../../data/library.dart';
import '../../data/notebook.dart';
import '../../data/sessions.dart';
import '../../data/settings.dart';
import '../../data/settings_provider.dart';
import '../../data/sync_service.dart';
import '../../ui/haptics.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../share/progress_shares.dart';
import '../share/share_sheet.dart';
import '../social/people_screen.dart';
import '../social/profile_header.dart';
import 'avatar_cropper.dart';
import '../../l10n/l10n.dart';

/// The reader's profile, Strava-style (Cloro plan §11): a header with your
/// photo, name, pronouns, follower counts, bio, the book you're reading and
/// up to 3 genres; then this week, your streak, stats, trophies, books and
/// saved quotes in one scroll. Progress shows growth (UX §5.8); nothing here
/// ranks you against anyone. Colour carries meaning, sparingly (UX §6.6):
/// blue is how much you read, green is keeping at it.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  /// The stats' period.
  StatsPeriod _period = StatsPeriod.month;

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    final s = ref.watch(settingsProvider);
    final habit = ref.watch(habitProvider);
    final notebook = ref.watch(notebookProvider);
    final books = ref.watch(libraryProvider);
    final notifier = ref.read(habitProvider.notifier);
    final streak = notifier.displayStreak();
    final now = DateTime.now();
    final goalMet = habit.today(now).meets(s.goal);
    final reading = ref.read(libraryProvider.notifier).current;
    final saved = notebook.saved.length + notebook.highlights.length;
    // Follower counts come from the server; offline they're left out.
    final me = ref.watch(apiProvider).enabled ? ref.watch(socialMeProvider).value : null;
    int? count(String k) => (me?[k] as num?)?.toInt();

    // The Profile tab: no back button, room for the tab bar.
    return KitPage(
      back: false,
      backdrop: false,
      dock: true,
      title: s.username.isEmpty ? s.displayName : '@${s.username}',
      onRefresh: me == null ? null : () async => ref.invalidate(socialMeProvider),
      actions: [
        KitIconButton(icon: Icons.person_add_alt_1_rounded, semanticLabel: tr('Find people'), onPressed: () => context.push('/people/me?tab=following')),
        KitIconButton(icon: Icons.settings_rounded, semanticLabel: tr('Settings'), onPressed: () => context.push('/settings')),
      ],
      children: [
        ProfileHeader(
          avatar: KitPressable(
            onTap: () => showEditProfile(context),
            semanticLabel: tr('Profile photo. Edit profile'),
            excludeSemantics: true,
            child: ReaderAvatar(settings: s, size: 88, ring: goalMet),
          ),
          name: s.displayName,
          pronouns: s.pronouns,
          followers: count('followers'),
          following: count('following'),
          onFollowers: () => context.push('/people/me?tab=followers'),
          onFollowing: () => context.push('/people/me?tab=following'),
          bio: s.bio,
          onAddBio: () => showEditProfile(context),
          reading: reading?.title,
          onReading: reading == null ? null : () => context.go('/read/${reading.id}'),
          genres: s.interests,
          actions: [
            KitButton.secondary(label: tr('Edit profile'), compact: true, expand: true, onPressed: () => showEditProfile(context)),
            KitButton.secondary(
              label: tr('Share'),
              compact: true,
              expand: true,
              onPressed: () => showShareSheet(
                context,
                profileShare(
                  name: s.displayName,
                  handle: s.username,
                  emoji: s.avatarEmoji.isNotEmpty ? s.avatarEmoji : '📖',
                  reading: reading?.title,
                  habit: habit,
                  streak: streak,
                  booksFinished: math.max(habit.booksFinished, books.where((b) => b.finishedAt != null).length),
                ),
              ),
            ),
          ],
        ),
        _LastSevenDays(habit: habit, sessions: ref.watch(sessionLogProvider), now: now),
        _Section(
          title: tr('Streak'),
          child: _StreakSection(
            habit: habit,
            settings: s,
            streak: streak,
            freezes: notifier.freezesLeft(),
          ),
        ),
        _Section(
          title: tr('Stats'),
          child: _StatsSection(
            habit: habit,
            notebook: notebook,
            books: books,
            now: now,
            period: _period,
            onChanged: (v) => setState(() => _period = v),
          ),
        ),
        _Section(title: tr('Trophies'), child: _Trophies(habit: habit, books: books)),
        _Section(title: tr('Books'), child: _BooksSection(books: books)),
        _Section(
          title: tr('Saved quotes'),
          trailing: saved == 0 ? null : Text('$saved', style: kit.caption),
          child: _QuotesGrid(notebook: notebook),
        ),
      ],
    );
  }
}

/// One part of the profile: a line above, a heading, then its content (no boxes).
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.trailing});
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 8),
      const KitDivider(),
      const SizedBox(height: 4),
      Row(children: [
        Expanded(child: Semantics(header: true, child: Text(title, style: kit.heading.copyWith(fontSize: 17)))),
        ?trailing,
      ]),
      const SizedBox(height: 12),
      child,
    ]);
  }
}

/// A number and what it counts, on the very light shade of its kind
/// ([hue]: time and amounts blue, keeping at it green, words purple…); the
/// headline number of a section in its kind's colour.
class _Figure extends StatelessWidget {
  const _Figure(this.value, this.label, {this.hue = KitHue.neutral, this.headline = false});
  final String value;
  final String label;
  final KitHue hue;
  final bool headline;

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    return Semantics(
      container: true,
      label: '$value $label',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: DecoratedBox(
          decoration: BoxDecoration(color: kit.shade(hue), borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 8, 9),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value, style: kit.title.copyWith(fontSize: 22, color: headline ? kit.hue(hue) : null)),
              Text(label, style: kit.caption.copyWith(fontSize: 12.5)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The last seven days, Strava-style: a blue circle round each day whose
/// area grows with the minutes read that day (the best of the seven is the
/// largest), their totals above, and the figures of the day you tap below.
/// The arrows by the title (or a swipe across the days) go back a week at a
/// time, as far as the first day read.
class _LastSevenDays extends StatefulWidget {
  const _LastSevenDays({required this.habit, required this.sessions, required this.now});
  final HabitState habit;
  final List<ReadingSession> sessions;
  final DateTime now;

  @override
  State<_LastSevenDays> createState() => _LastSevenDaysState();
}

class _LastSevenDaysState extends State<_LastSevenDays> {
  /// How many weeks back: 0 is the seven days up to today.
  int _back = 0;

  /// The day tapped (0 is the first of the seven); the last until then.
  int? _picked;

  DateTime get _today => DateTime(widget.now.year, widget.now.month, widget.now.day);

  /// The furthest back there's anything to show: the week holding the first
  /// day read.
  int get _oldest {
    DateTime? first;
    for (final k in widget.habit.stats.keys) {
      final d = parseDateKey(k);
      if (first == null || d.isBefore(first)) first = d;
    }
    if (first == null) return 0;
    return math.max(0, _today.difference(first).inDays ~/ 7);
  }

  void _go(int back) {
    final next = back.clamp(0, _oldest);
    if (next == _back) return;
    Haptics.select();
    setState(() {
      _back = next;
      _picked = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    final today = _today;
    final end = DateTime(today.year, today.month, today.day - 7 * _back);
    final days = [for (var d = 6; d >= 0; d--) DateTime(end.year, end.month, end.day - d)];
    final stats = [for (final d in days) widget.habit.stats[dateKey(d)] ?? const DailyStat()];
    final minutes = stats.fold(0.0, (s, d) => s + d.minutes);
    final cards = stats.fold(0, (s, d) => s + d.verifiedCards);
    final words = stats.fold(0, (s, d) => s + d.words);
    final after = DateTime(end.year, end.month, end.day + 1);
    final read = {
      for (final s in widget.sessions)
        if (!s.startedAt.isBefore(days.first) && s.startedAt.isBefore(after)) s.bookId,
    }.length;
    final top = stats.fold(0.0, (m, d) => math.max(m, d.minutes));
    final latest = _back == 0;
    final picked = _picked ?? 6;
    final day = stats[picked];
    final letter = localDate('EEEEE'), name = localDate('EEEE'), short = localDate('MMMd');
    String dayName(int i) => latest && i == 6 ? tr('Today') : name.format(days[i]);
    final title = latest ? tr('Last 7 days') : '${short.format(days.first)} – ${short.format(end)}';
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return _Section(
      title: title,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        KitIconButton(
          icon: Icons.chevron_left_rounded,
          semanticLabel: tr('Older days'),
          glass: false,
          onPressed: _back < _oldest ? () => _go(_back + 1) : null,
        ),
        KitIconButton(
          icon: Icons.chevron_right_rounded,
          semanticLabel: tr('Newer days'),
          glass: false,
          onPressed: latest ? null : () => _go(_back - 1),
        ),
      ]),
      child: GestureDetector(
        // A swipe across the days: towards the past, or back again.
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v.abs() < 200) return;
          _go((v > 0) != rtl ? _back + 1 : _back - 1);
        },
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: _Figure('${minutes.round()}', trn(minutes.round(), 'minute', 'minutes'), hue: KitHue.activity, headline: true)),
            Expanded(child: _Figure('$cards', trn(cards, 'card', 'cards'), hue: KitHue.activity)),
            Expanded(child: _Figure(compactCount(words), tr('words'), hue: KitHue.activity)),
            Expanded(child: _Figure('$read', trn(read, 'book', 'books'), hue: KitHue.growth)),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: DayCircle(
                  letter: letter.format(days[i]),
                  minutes: stats[i].minutes,
                  most: top,
                  today: latest && i == 6,
                  picked: i == picked,
                  semanticLabel: '${latest && i == 6 ? tr('{day}, today', {'day': name.format(days[i])}) : '${name.format(days[i])} ${short.format(days[i])}'}: '
                      '${trn(stats[i].minutes.round(), '{n} minute', '{n} minutes')}, ${trn(stats[i].verifiedCards, '{n} card', '{n} cards')}',
                  onTap: () {
                    Haptics.select();
                    setState(() => _picked = i);
                  },
                ),
              ),
          ]),
          const SizedBox(height: 8),
          ExcludeSemantics(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: dayName(picked), style: TextStyle(color: kit.ink, fontWeight: FontWeight.w700)),
                if (!(latest && picked == 6)) TextSpan(text: ' ${short.format(days[picked])}', style: TextStyle(color: kit.ink, fontWeight: FontWeight.w700)),
                const TextSpan(text: '  ·  '),
                TextSpan(text: tr('{n} min', {'n': day.minutes.round()}), style: TextStyle(color: kit.activity, fontWeight: FontWeight.w800)),
                TextSpan(text: '  ·  ${trn(day.verifiedCards, '{n} card', '{n} cards')}'),
                if (day.words > 0) TextSpan(text: '  ·  ${tr('{count} words', {'count': compactCount(day.words)})}'),
              ]),
              textAlign: TextAlign.center,
              style: kit.caption.copyWith(fontSize: 13),
            ),
          ),
        ]),
      ),
    );
  }
}

/// A day of the week inside a blue circle sized by the minutes read: its
/// area grows in proportion, from [smallest] across (a minute) to [largest]
/// (the week's best day). A day without reading is an empty ring; today is
/// ringed in blue until you read; the day picked has a dot below.
class DayCircle extends StatelessWidget {
  const DayCircle({
    super.key,
    required this.letter,
    required this.minutes,
    required this.most,
    required this.semanticLabel,
    this.today = false,
    this.future = false,
    this.picked = false,
    this.onTap,
  });

  static const smallest = 26.0;
  static const largest = 44.0;

  final String letter;
  final double minutes;

  /// The most minutes read on a day this week.
  final double most;
  final String semanticLabel;
  final bool today;
  final bool future;
  final bool picked;
  final VoidCallback? onTap;

  /// The circle's diameter: its area in proportion to [minutes] over [most].
  static double diameterFor(double minutes, double most) {
    if (minutes <= 0 || most <= 0) return smallest;
    final share = (minutes / most).clamp(0.0, 1.0);
    return math.sqrt(smallest * smallest + (largest * largest - smallest * smallest) * share);
  }

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    final read = minutes > 0;
    final size = diameterFor(minutes, most);
    final still = MediaQuery.disableAnimationsOf(context);
    return KitPressable(
      onTap: onTap,
      selected: picked,
      semanticLabel: semanticLabel,
      excludeSemantics: true,
      pressedScale: 0.9,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          height: largest + 2,
          child: Center(
            child: AnimatedContainer(
              duration: Duration(milliseconds: still ? 0 : 320),
              curve: Curves.easeOutCubic,
              width: size,
              height: size,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: read ? kit.activity : null,
                border: read ? null : Border.all(color: today ? kit.activity : kit.stroke, width: today ? 2 : 1),
              ),
              child: Text(
                letter,
                style: kit.caption.copyWith(
                  fontSize: 12.5,
                  height: 1,
                  fontWeight: today ? FontWeight.w800 : FontWeight.w600,
                  color: read ? kit.inverse : (future ? kit.inkSoft.withValues(alpha: 0.45) : kit.inkSoft),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        AnimatedOpacity(
          opacity: picked ? 1 : 0,
          duration: Duration(milliseconds: still ? 0 : 200),
          child: Container(width: 4, height: 4, decoration: BoxDecoration(color: kit.ink, shape: BoxShape.circle)),
        ),
      ]),
    );
  }
}

class _StreakSection extends StatelessWidget {
  const _StreakSection({required this.habit, required this.settings, required this.streak, required this.freezes});
  final HabitState habit;
  final AppSettings settings;
  final int streak;
  final int freezes;

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    final weekly = settings.goalMode == GoalMode.weekly;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: _Figure('$streak', weekly ? tr('week streak') : tr('day streak'), hue: KitHue.growth, headline: streak > 0)),
        Expanded(child: _Figure('${habit.streak.best}', tr('best'), hue: KitHue.growth)),
        Expanded(child: _Figure('$freezes', trn(freezes, 'freeze left', 'freezes left'), hue: KitHue.activity)),
      ]),
      const SizedBox(height: 16),
      StreakCalendar(stats: habit.stats, goal: settings.goal, now: DateTime.now()),
      const SizedBox(height: 8),
      // GitHub's key: from no reading to the goal met.
      Row(children: [
        Expanded(child: Text(tr('Last 12 weeks'), style: kit.caption.copyWith(fontSize: 12.5))),
        ExcludeSemantics(
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(tr('Less'), style: kit.caption.copyWith(fontSize: 11.5)),
            const SizedBox(width: 4),
            for (final c in kit.streakScale)
              Container(
                width: 11,
                height: 11,
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2.5)),
              ),
            const SizedBox(width: 4),
            Text(tr('More'), style: kit.caption.copyWith(fontSize: 11.5)),
          ]),
        ),
      ]),
    ]);
  }
}

/// The stats' period on the Profile.
enum StatsPeriod {
  month,
  year,
  all;

  String get label => switch (this) {
        StatsPeriod.month => tr('This month'),
        StatsPeriod.year => tr('This year'),
        StatsPeriod.all => tr('All time'),
      };

  /// Whether a day (a date key) falls in the period around [now].
  bool covers(String day, DateTime now) => switch (this) {
        StatsPeriod.month => day.startsWith('${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-'),
        StatsPeriod.year => day.startsWith('${now.year.toString().padLeft(4, '0')}-'),
        StatsPeriod.all => true,
      };
}

/// This month, this year or all time: minutes, cards, books, reading days
/// and more. Reading time is in blue, books finished and reading days in
/// green; the rest stay plain.
class _StatsSection extends StatelessWidget {
  const _StatsSection({
    required this.habit,
    required this.notebook,
    required this.books,
    required this.now,
    required this.period,
    required this.onChanged,
  });
  final HabitState habit;
  final NotebookState notebook;
  final List<BookMeta> books;
  final DateTime now;
  final StatsPeriod period;
  final ValueChanged<StatsPeriod> onChanged;

  @override
  Widget build(BuildContext context) {
    final days = [
      for (final e in habit.stats.entries)
        if (period.covers(e.key, now)) e.value,
    ];
    final minutes = days.fold(0.0, (s, d) => s + d.minutes);
    final cards = days.fold(0, (s, d) => s + d.verifiedCards);
    final words = days.fold(0, (s, d) => s + d.words);
    final skimmed = days.fold(0, (s, d) => s + d.skimmedCards);
    final readingDays = days.where((d) => d.minutes > 0 || d.verifiedCards > 0).length;
    final finished = period == StatsPeriod.all
        ? math.max(habit.booksFinished, books.where((b) => b.finishedAt != null).length)
        : books.where((b) => b.finishedAt != null && period.covers(dateKey(b.finishedAt!), now)).length;
    final figures = [
      _Figure(_duration(minutes), tr('reading time'), hue: KitHue.activity, headline: true),
      _Figure('$cards', trn(cards, 'card', 'cards'), hue: KitHue.activity),
      _Figure(compactCount(words), tr('words read'), hue: KitHue.activity),
      // Honest about it: reels flicked past too fast to read count toward nothing.
      _Figure('$skimmed', trn(skimmed, 'reel skimmed (not counted)', 'reels skimmed (not counted)')),
      _Figure('$finished', trn(finished, 'book finished', 'books finished'), hue: KitHue.growth, headline: finished > 0),
      _Figure('$readingDays', trn(readingDays, 'reading day', 'reading days'), hue: KitHue.growth, headline: readingDays > 0),
      _Figure(readingDays == 0 ? '0' : '${(minutes / readingDays).round()}', tr('minutes a reading day'), hue: KitHue.activity),
      if (period == StatsPeriod.all)
        _Figure('${notebook.words.length}', tr('words learned'), hue: KitHue.words)
      else
        _Figure('${habit.wpm.round()}', tr('words a minute'), hue: KitHue.activity),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      KitSegmented<StatsPeriod>(values: StatsPeriod.values, selected: period, label: (p) => p.label, onChanged: onChanged),
      const SizedBox(height: 14),
      for (var i = 0; i < figures.length; i += 2)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(children: [Expanded(child: figures[i]), Expanded(child: figures[i + 1])]),
        ),
    ]);
  }

  static String _duration(double minutes) {
    final m = minutes.round();
    if (m < 60) return tr('{n} min', {'n': m});
    return m % 60 == 0 ? tr('{h} h', {'h': m ~/ 60}) : tr('{h} h {m} min', {'h': m ~/ 60, 'm': m % 60});
  }
}

/// A milestone: earned, or the next one to aim for.
class Trophy {
  const Trophy(this.emoji, this.title, {required this.earned});
  final String emoji;
  final String title;
  final bool earned;
}

const _bookMilestones = [1, 5, 10, 25, 50, 100];
const _cardMilestones = [100, 500, 1000, 5000, 10000];

/// Trophies earned so far, then the next of each kind.
List<Trophy> trophiesFor({required int bestStreak, required int booksFinished, required int cards, required double bestWeekMinutes}) {
  List<Trophy> ladder(List<int> steps, int value, String emoji, String Function(int) title) {
    final earned = [for (final s in steps) if (value >= s) Trophy(emoji, title(s), earned: true)];
    final next = steps.where((s) => value < s).firstOrNull;
    return [...earned, if (next != null) Trophy(emoji, title(next), earned: false)];
  }

  return [
    ...ladder(streakMilestones, bestStreak, '🔥', (n) => tr('{n}-day streak', {'n': n})),
    ...ladder(_bookMilestones, booksFinished, '📚', (n) => n == 1 ? tr('First book') : trn(n, '{n} book', '{n} books')),
    ...ladder(_cardMilestones, cards, '🃏', (n) => trn(n, '{n} card', '{n} cards')),
    if (bestWeekMinutes >= 1) Trophy('⏱️', tr('Best week: {n} min', {'n': bestWeekMinutes.round()}), earned: true),
  ];
}

class _Trophies extends StatelessWidget {
  const _Trophies({required this.habit, required this.books});
  final HabitState habit;
  final List<BookMeta> books;

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    final weeks = <String, double>{};
    for (final e in habit.stats.entries) {
      final w = weekKey(parseDateKey(e.key));
      weeks[w] = (weeks[w] ?? 0) + e.value.minutes;
    }
    final trophies = trophiesFor(
      bestStreak: habit.streak.best,
      booksFinished: math.max(habit.booksFinished, books.where((b) => b.finishedAt != null).length),
      cards: habit.totalVerifiedCards,
      bestWeekMinutes: weeks.values.fold(0.0, math.max),
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!trophies.any((t) => t.earned)) ...[
        Text(tr('Your first trophies are close.'), style: kit.caption),
        const SizedBox(height: 12),
      ],
      Wrap(spacing: 10, runSpacing: 14, children: [
        for (final t in trophies)
          Semantics(
            container: true,
            label: t.earned ? tr('Trophy: {title}', {'title': t.title}) : tr('Next trophy: {title}', {'title': t.title}),
            excludeSemantics: true,
            child: Opacity(
              opacity: t.earned ? 1 : 0.38,
              child: SizedBox(
                width: 78,
                child: Column(children: [
                  Container(
                    width: 56,
                    height: 56,
                    alignment: Alignment.center,
                    // Earned on a faint green (keeping at it); the next one plain.
                    decoration: BoxDecoration(color: t.earned ? kit.growthSoft : kit.field, shape: BoxShape.circle),
                    child: Text(t.emoji, style: const TextStyle(fontSize: 26)),
                  ),
                  const SizedBox(height: 6),
                  Text(t.earned ? t.title : tr('Next: {title}', {'title': t.title}),
                      textAlign: TextAlign.center, maxLines: 2, style: kit.caption.copyWith(fontSize: 12, color: kit.ink)),
                ]),
              ),
            ),
          ),
      ]),
    ]);
  }
}

/// Reading now (with progress rings), then finished.
class _BooksSection extends StatelessWidget {
  const _BooksSection({required this.books});
  final List<BookMeta> books;

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    if (books.isEmpty) return KitEmpty(emoji: '📚', title: tr('No books yet'), message: tr('Import a book from the Library.'));
    final reading = [for (final b in books) if (b.finishedAt == null) b]
      ..sort((a, b) => (b.lastReadAt ?? DateTime(0)).compareTo(a.lastReadAt ?? DateTime(0)));
    final finished = [for (final b in books) if (b.finishedAt != null) b]..sort((a, b) => b.finishedAt!.compareTo(a.finishedAt!));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (reading.isNotEmpty)
        SizedBox(
          height: 102,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: reading.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, i) {
              final b = reading[i];
              return KitPressable(
                onTap: () => context.go('/read/${b.id}'),
                semanticLabel: tr('{title}, {percent}% read', {'title': b.title, 'percent': (b.progress * 100).round()}),
                excludeSemantics: true,
                child: SizedBox(
                  width: 72,
                  child: Column(children: [
                    _ShelfCircle(book: b, size: 70),
                    const SizedBox(height: 6),
                    Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: kit.caption.copyWith(fontSize: 12, color: kit.ink)),
                  ]),
                ),
              );
            },
          ),
        ),
      if (finished.isNotEmpty) ...[
        const SizedBox(height: 10),
        Text(tr('Finished'), style: kit.label),
        KitGroup(children: [
          for (final b in finished)
            KitRow(
              leading: ClipRRect(borderRadius: BorderRadius.circular(4), child: BookCover(book: b, width: 38)),
              title: b.title,
              subtitle: b.author,
              onTap: () => context.go('/read/${b.id}'),
            ),
        ]),
      ],
    ]);
  }
}

/// The reader's picture: their photo, an emoji, or their initial; with a
/// green ring once today's goal is done (like a story ring).
class ReaderAvatar extends StatelessWidget {
  const ReaderAvatar({super.key, required this.settings, this.size = 40, this.ring = false});

  final AppSettings settings;
  final double size;
  final bool ring;

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    final path = settings.avatarPath;
    final name = settings.displayName.trim();
    Widget inner;
    if (path != null && fileExists(path)) {
      inner = Image.file(File(path), fit: BoxFit.cover, cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round());
    } else if (settings.avatarEmoji.isNotEmpty) {
      inner = ColoredBox(color: kit.field, child: Center(child: Text(settings.avatarEmoji, style: TextStyle(fontSize: size * 0.5))));
    } else {
      inner = DecoratedBox(
        decoration: BoxDecoration(color: kit.field),
        child: Center(
          child: Text(name.isEmpty || name == 'Reader' ? '📖' : name.characters.first.toUpperCase(),
              style: kit.title.copyWith(color: kit.ink, fontSize: size * 0.42)),
        ),
      );
    }
    final avatar = ClipOval(child: SizedBox(width: size, height: size, child: inner));
    if (!ring) return avatar;
    return Container(
      padding: EdgeInsets.all(size * 0.04),
      decoration: BoxDecoration(shape: BoxShape.circle, color: kit.growth),
      child: Container(
        padding: EdgeInsets.all(size * 0.035),
        decoration: BoxDecoration(shape: BoxShape.circle, color: kit.base),
        child: avatar,
      ),
    );
  }
}

class _ShelfCircle extends StatelessWidget {
  const _ShelfCircle({required this.book, required this.size});
  final BookMeta book;
  final double size;

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    final b = book;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ProgressRing(progress: b.progress.clamp(0.0, 1.0), color: kit.activity, track: kit.activitySoft),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: ClipOval(child: FittedBox(fit: BoxFit.cover, child: BookCover(book: b, width: 64))),
        ),
      ),
    );
  }
}

class _ProgressRing extends CustomPainter {
  _ProgressRing({required this.progress, required this.color, required this.track});
  final double progress;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(1.5);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 6.2832, false, p..color = track);
    if (progress > 0) canvas.drawArc(rect, -1.5708, 6.2832 * progress, false, p..color = color);
  }

  @override
  bool shouldRepaint(_ProgressRing old) => old.progress != progress || old.color != color || old.track != track;
}

/// Saved cards and highlights as a grid of quote tiles, newest first.
class _QuotesGrid extends StatelessWidget {
  const _QuotesGrid({required this.notebook});
  final NotebookState notebook;

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    final colors = ReadingTheme.of(ReadingThemeId.paper).highlights;
    final items = [
      for (final s in notebook.saved) (at: s.createdAt, text: s.text, link: '/read/${s.bookId}?sid=${s.startSid}', tint: kit.ink, saved: true),
      for (final h in notebook.highlights)
        (at: h.createdAt, text: h.text, link: '/read/${h.bookId}?sid=${h.sid}', tint: colors[h.color % colors.length].withValues(alpha: 1), saved: false),
    ]..sort((a, b) => b.at.compareTo(a.at));
    if (items.isEmpty) {
      return KitEmpty(emoji: '🔖', title: tr('No quotes yet'), message: tr('Save a card or highlight a line, and it shows up here.'));
    }
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      children: [
        for (final q in items)
          KitPressable(
            onTap: () => context.go(q.link),
            pressedScale: 0.97,
            semanticLabel: q.text,
            excludeSemantics: true,
            child: Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color.alphaBlend(q.tint.withValues(alpha: 0.32), kit.base), Color.alphaBlend(q.tint.withValues(alpha: 0.12), kit.base)],
                ),
              ),
              child: Stack(children: [
                Text(q.text,
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: 'Literata', fontSize: 11.5, height: 1.3, color: kit.ink)),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Icon(q.saved ? Icons.bookmark_rounded : Icons.border_color_rounded, size: 14, color: q.tint),
                ),
              ]),
            ),
          ),
      ],
    );
  }
}

/// How much of a day's goal was read, as GitHub's contribution levels: 0
/// for no reading, 1–3 for under a third, two thirds or the whole goal,
/// and 4 once the goal is met.
int streakLevel(DailyStat? day, GoalConfig goal) {
  if (day == null) return 0;
  if (day.meets(goal)) return 4;
  final p = day.progress(goal);
  if (p <= 0) return day.minutes > 0 || day.verifiedCards > 0 ? 1 : 0;
  return p < 1 / 3 ? 1 : (p < 2 / 3 ? 2 : 3);
}

/// The last 12 weeks, a column a week from Monday, in GitHub's contribution
/// greens: the deeper the green, the more of the day's goal was read. Days
/// still to come this week are left blank.
class StreakCalendar extends StatelessWidget {
  const StreakCalendar({super.key, required this.stats, required this.goal, required this.now});
  final Map<String, DailyStat> stats;
  final GoalConfig goal;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final scale = Kit.of(context).streakScale;
    final monday = parseDateKey(weekKey(now));
    final start = DateTime(monday.year, monday.month, monday.day - 7 * 11);
    final today = DateTime(now.year, now.month, now.day);
    var reading = 0, met = 0;
    for (var i = 0; i < 84; i++) {
      final level = streakLevel(stats[dateKey(DateTime(start.year, start.month, start.day + i))], goal);
      if (level > 0) reading++;
      if (level == 4) met++;
    }
    return Semantics(
      container: true,
      label: tr('Reading calendar for the last 12 weeks: {days}, the goal met on {met}',
          {'days': trn(reading, '{n} day with reading', '{n} days with reading'), 'met': met}),
      excludeSemantics: true,
      child: LayoutBuilder(builder: (context, c) {
        // Twelve columns across the width, square cells with a small gap.
        final cell = math.min(18.0, (c.maxWidth / 12) - 3);
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var w = 0; w < 12; w++)
              Column(children: [
                for (var d = 0; d < 7; d++)
                  Builder(builder: (context) {
                    final day = DateTime(start.year, start.month, start.day + w * 7 + d);
                    final future = day.isAfter(today);
                    return Container(
                      margin: const EdgeInsets.all(1.5),
                      width: cell,
                      height: cell,
                      decoration: BoxDecoration(
                        color: future ? null : scale[streakLevel(stats[dateKey(day)], goal)],
                        borderRadius: BorderRadius.circular(cell * 0.22),
                      ),
                    );
                  }),
              ]),
          ],
        );
      }),
    );
  }
}

// ---------------------------------------------------------------- editing

/// Edit profile: photo or emoji, name, @username, pronouns, bio, genres.
Future<void> showEditProfile(BuildContext context) =>
    showKitSheet<void>(context, title: tr('Edit profile'), maxHeight: 0.94, builder: (_) => const _EditProfile());

/// Pronouns to pick from; anything else is "Custom".
/// (Shown as written: other readers see them too.)
const pronounChoices = ['he/him', 'she/her', 'they/them'];

/// Favourite genres shown on a profile.
const maxGenres = 3;

const _avatarEmoji = ['📚', '📖', '🦉', '🌙', '🌲', '☕', '🌊', '🌸', '🦊', '🐱', '🐼', '🦁', '🐢', '🌻', '🍵', '🎧', '✏️', '🧠', '🚀', '🌈', '🍂', '❄️', '🔥', '✨'];

class _EditProfile extends ConsumerStatefulWidget {
  const _EditProfile();

  @override
  ConsumerState<_EditProfile> createState() => _EditProfileState();
}

/// Links in a name or bio (the server refuses them too: spam).
final _profileLink = RegExp(r'(https?://|www\.|\b[a-z0-9-]{2,}\.(com|net|org|io|xyz|ru|cn|info|biz|top|link|click|site|online|shop|live|app|me|ly|gg|co|in)\b)', caseSensitive: false);

class _EditProfileState extends ConsumerState<_EditProfile> {
  late final AppSettings _start = ref.read(settingsProvider);
  late final _name = TextEditingController(text: _start.displayName == 'Reader' ? '' : _start.displayName);
  late final _username = TextEditingController(text: _start.username);
  late final _pronouns = TextEditingController(text: pronounChoices.contains(_start.pronouns) ? '' : _start.pronouns);
  late final _bio = TextEditingController(text: _start.bio);

  /// One of [pronounChoices], 'custom', or '' (none).
  late String _pronounChoice = pronounChoices.contains(_start.pronouns)
      ? _start.pronouns
      : _start.pronouns.isEmpty
          ? ''
          : 'custom';
  late Set<String> _genres = {..._start.interests.take(maxGenres)};
  late String _emoji = _start.avatarEmoji;
  late String? _photo = _start.avatarPath;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _username, _pronouns, _bio]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final files = await FilePicker.pickFiles(type: FileType.image);
    if (files.isEmpty || !mounted) return;
    final picked = await files.first.readAsBytes();
    if (!mounted) return;
    // Move and scale it inside the circle; a square PNG comes back.
    final cropped = await showAvatarCropper(context, picked);
    if (cropped == null || !mounted) return;
    final dir = await getApplicationDocumentsDirectory();
    // A new name each time, so no cached copy of an older photo shows.
    final out = File('${dir.path}/avatar_${DateTime.now().millisecondsSinceEpoch}.png');
    await out.writeAsBytes(cropped);
    if (mounted) setState(() => _photo = out.path);
  }

  Future<void> _pickEmoji() async {
    final picked = await showKitSheet<String>(
      context,
      title: tr('Pick an emoji'),
      builder: (context) => Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [
        for (final e in _avatarEmoji)
          KitPressable(
            onTap: () => Navigator.of(context).pop(e),
            semanticLabel: e,
            child: SizedBox(width: 52, height: 52, child: Center(child: Text(e, style: const TextStyle(fontSize: 30)))),
          ),
      ]),
    );
    if (picked == null) return;
    setState(() {
      _emoji = picked;
      _photo = null;
    });
  }

  Future<void> _save() async {
    final username = _username.text.trim().replaceFirst(RegExp('^@'), '').toLowerCase();
    if (username.isNotEmpty && !usernamePattern.hasMatch(username)) {
      setState(() => _error = tr('Usernames are 3–24 letters, numbers, dots or underscores.'));
      return;
    }
    // Other readers see these: no links (the server checks the same).
    if (_profileLink.hasMatch(_name.text) || _profileLink.hasMatch(_bio.text)) {
      setState(() => _error = tr('Links aren’t allowed in your name or bio.'));
      return;
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    final api = ref.read(apiProvider);
    if (api.enabled) {
      // Check with the server first: the name must be free, and what others
      // see must pass its checks, so a refusal shows here and now.
      try {
        await api.updateProfile(
          handle: username != _start.username ? username : null,
          displayName: _name.text.trim().isEmpty ? 'Reader' : _name.text.trim(),
          pronouns: _pronounChoice == 'custom' ? _pronouns.text.trim() : _pronounChoice,
          bio: _bio.text.trim(),
        );
      } on ApiException catch (e) {
        if (e.status == 409 || e.status == 400) {
          if (mounted) {
            setState(() {
              _error = e.status == 400 && e.message != null ? e.message! : tr('@{username} is taken. Try another.', {'username': username});
              _saving = false;
            });
          }
          return;
        }
      } catch (_) {
        // Offline: saved here and synced later.
      }
    }
    final old = _start.avatarPath;
    ref.read(settingsProvider.notifier).update((x) => x.copyWith(
          displayName: _name.text.trim().isEmpty ? 'Reader' : _name.text.trim(),
          username: username,
          pronouns: _pronounChoice == 'custom' ? _pronouns.text.trim() : _pronounChoice,
          bio: _bio.text.trim(),
          interests: _genres.toList(),
          avatarEmoji: _emoji,
          avatarPath: _photo,
          clearAvatarPath: _photo == null,
        ));
    if (old != null && old != _photo) {
      try {
        await File(old).delete();
      } catch (_) {}
    }
    if (api.enabled) unawaited(ref.read(syncServiceProvider).syncNow());
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    final preview = ref.read(settingsProvider).copyWith(
          displayName: _name.text.trim().isEmpty ? 'Reader' : _name.text.trim(),
          avatarEmoji: _emoji,
          avatarPath: _photo,
          clearAvatarPath: _photo == null,
        );
    Widget label(String t) => Padding(padding: const EdgeInsets.only(top: 14, bottom: 6), child: Text(t, style: kit.label));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Center(child: ReaderAvatar(settings: preview, size: 84)),
      const SizedBox(height: 10),
      Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
        KitChip(label: tr('Photo'), icon: Icons.photo_rounded, onTap: _pickPhoto),
        KitChip(label: tr('Emoji'), icon: Icons.emoji_emotions_rounded, onTap: _pickEmoji),
        if (_photo != null || _emoji.isNotEmpty)
          KitChip(
            label: tr('Remove'),
            icon: Icons.close_rounded,
            onTap: () => setState(() {
              _emoji = '';
              _photo = null;
            }),
          ),
      ]),
      label(tr('NAME')),
      KitTextField(controller: _name, hint: tr('Your name'), capitalization: TextCapitalization.words, maxLength: 40, onChanged: (_) => setState(() {})),
      label(tr('USERNAME')),
      KitTextField(controller: _username, hint: tr('@yourname'), capitalization: TextCapitalization.none, maxLength: 25),
      label(tr('PRONOUNS')),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final p in [...pronounChoices, 'custom'])
          KitChip(
            label: p == 'custom' ? tr('Custom') : p,
            selected: _pronounChoice == p,
            onTap: () => setState(() => _pronounChoice = _pronounChoice == p ? '' : p),
          ),
      ]),
      if (_pronounChoice == 'custom') ...[
        const SizedBox(height: 8),
        KitTextField(controller: _pronouns, hint: tr('Your pronouns'), capitalization: TextCapitalization.none, maxLength: 30),
      ],
      label(tr('BIO')),
      KitTextField(controller: _bio, hint: tr('What you love to read, and why'), maxLines: 4, minLines: 2, maxLength: 150),
      label(tr('FAVOURITE GENRES')),
      Text(
        _genres.length >= maxGenres ? tr('Pick up to {max} (that’s {max})', {'max': maxGenres}) : tr('Pick up to {max} ({left} left)', {'max': maxGenres, 'left': maxGenres - _genres.length}),
        style: kit.caption,
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final g in readingGenres)
          Builder(builder: (context) {
            final on = _genres.contains(g);
            final full = !on && _genres.length >= maxGenres;
            return Opacity(
              opacity: full ? 0.4 : 1,
              child: KitChip(
                label: tr(g),
                selected: on,
                onTap: full ? null : () => setState(() => _genres = on ? ({..._genres}..remove(g)) : {..._genres, g}),
              ),
            );
          }),
      ]),
      if (_error != null) ...[
        const SizedBox(height: 12),
        Text(_error!, style: kit.caption.copyWith(color: kit.danger)),
      ],
      const SizedBox(height: 18),
      KitButton(label: _saving ? tr('Saving…') : tr('Save'), expand: true, onPressed: _saving ? null : _save),
    ]);
  }
}
