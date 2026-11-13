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
import '../../data/settings.dart';
import '../../data/settings_provider.dart';
import '../../data/sync_service.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../share/share_sheet.dart';
import '../social/people_screen.dart';
import '../social/profile_header.dart';
import 'avatar_cropper.dart';

/// The reader's profile, Strava-style (Cloro plan §11): a header with your
/// photo, name, pronouns, follower counts, bio, the book you're reading and
/// up to 3 genres; then this week, your streak, stats, trophies, books and
/// saved quotes in one scroll. Progress shows growth (UX §5.8); nothing here
/// ranks you against anyone.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  /// Stats for this year (or all time).
  bool _thisYear = true;

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
        KitIconButton(icon: Icons.person_add_alt_1_rounded, semanticLabel: 'Find people', onPressed: () => context.push('/people/me?tab=following')),
        KitIconButton(icon: Icons.settings_rounded, semanticLabel: 'Settings', onPressed: () => context.push('/settings')),
      ],
      children: [
        ProfileHeader(
          avatar: KitPressable(
            onTap: () => showEditProfile(context),
            semanticLabel: 'Profile photo. Edit profile',
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
            KitButton.secondary(label: 'Edit profile', compact: true, expand: true, onPressed: () => showEditProfile(context)),
            KitButton.secondary(
              label: 'Share',
              compact: true,
              expand: true,
              onPressed: () => showShareSheet(
                context,
                ProgressShare(
                  emoji: s.avatarEmoji.isNotEmpty ? s.avatarEmoji : '📖',
                  headline: s.username.isEmpty ? '${s.displayName} on Cloro' : '${s.displayName} · @${s.username}',
                  lines: [
                    '$streak-day streak · ${habit.booksFinished} books finished',
                    if (reading != null) 'Reading ${reading.title}',
                  ],
                ),
              ),
            ),
          ],
        ),
        _Section(title: 'This week', child: _ThisWeek(habit: habit, books: books, now: now)),
        _Section(
          title: 'Streak',
          child: _StreakSection(
            habit: habit,
            settings: s,
            streak: streak,
            freezes: notifier.freezesLeft(),
          ),
        ),
        _Section(
          title: 'Stats',
          child: _StatsSection(
            habit: habit,
            notebook: notebook,
            books: books,
            now: now,
            thisYear: _thisYear,
            onChanged: (v) => setState(() => _thisYear = v),
          ),
        ),
        _Section(title: 'Trophies', child: _Trophies(habit: habit, books: books)),
        _Section(title: 'Books', child: _BooksSection(books: books)),
        _Section(
          title: 'Saved quotes',
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

/// A number and what it counts.
class _Figure extends StatelessWidget {
  const _Figure(this.value, this.label);
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    return Semantics(
      container: true,
      label: '$value $label',
      excludeSemantics: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: kit.title.copyWith(fontSize: 22)),
        Text(label, style: kit.caption.copyWith(fontSize: 12.5)),
      ]),
    );
  }
}

/// Minutes per day this week as bars, with the week's totals.
class _ThisWeek extends StatelessWidget {
  const _ThisWeek({required this.habit, required this.books, required this.now});
  final HabitState habit;
  final List<BookMeta> books;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    final monday = parseDateKey(weekKey(now));
    final days = [for (var d = 0; d < 7; d++) DateTime(monday.year, monday.month, monday.day + d)];
    final stats = [for (final d in days) habit.stats[dateKey(d)] ?? const DailyStat()];
    final minutes = stats.fold(0.0, (s, d) => s + d.minutes);
    final cards = stats.fold(0, (s, d) => s + d.verifiedCards);
    final read = books.where((b) => b.lastReadAt != null && !b.lastReadAt!.isBefore(monday)).length;
    final top = stats.fold(0.0, (m, d) => math.max(m, d.minutes));
    const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: _Figure('${minutes.round()}', 'minutes')),
        Expanded(child: _Figure('$cards', 'cards')),
        Expanded(child: _Figure('$read', read == 1 ? 'book' : 'books')),
      ]),
      const SizedBox(height: 16),
      Semantics(
        container: true,
        label: 'Minutes read each day this week: ${[for (var i = 0; i < 7; i++) '${letters[i]} ${stats[i].minutes.round()}'].join(', ')}',
        excludeSemantics: true,
        child: SizedBox(
          height: 92,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Container(
                    height: top == 0 ? 3 : math.max(3, 64 * stats[i].minutes / top),
                    margin: const EdgeInsets.symmetric(horizontal: 7),
                    decoration: BoxDecoration(
                      color: stats[i].minutes > 0 ? kit.ink : kit.field,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    letters[i],
                    style: kit.caption.copyWith(
                      fontSize: 12,
                      color: dateKey(days[i]) == dateKey(now) ? kit.ink : kit.inkSoft,
                      fontWeight: dateKey(days[i]) == dateKey(now) ? FontWeight.w800 : FontWeight.w500,
                    ),
                  ),
                ]),
              ),
          ]),
        ),
      ),
    ]);
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
        Expanded(child: _Figure('$streak', weekly ? 'week streak' : 'day streak')),
        Expanded(child: _Figure('${habit.streak.best}', 'best')),
        Expanded(child: _Figure('$freezes', freezes == 1 ? 'freeze left' : 'freezes left')),
      ]),
      const SizedBox(height: 16),
      _Heatmap(stats: habit.stats, goal: settings.goal),
      const SizedBox(height: 6),
      Text('Last 12 weeks', style: kit.caption.copyWith(fontSize: 12.5)),
    ]);
  }
}

/// This year or all time: minutes, cards, books, reading days and more.
class _StatsSection extends StatelessWidget {
  const _StatsSection({
    required this.habit,
    required this.notebook,
    required this.books,
    required this.now,
    required this.thisYear,
    required this.onChanged,
  });
  final HabitState habit;
  final NotebookState notebook;
  final List<BookMeta> books;
  final DateTime now;
  final bool thisYear;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final year = '${now.year}-';
    final days = [
      for (final e in habit.stats.entries)
        if (!thisYear || e.key.startsWith(year)) e.value,
    ];
    final minutes = days.fold(0.0, (s, d) => s + d.minutes);
    final cards = days.fold(0, (s, d) => s + d.verifiedCards);
    final readingDays = days.where((d) => d.minutes > 0 || d.verifiedCards > 0).length;
    final finished = thisYear
        ? books.where((b) => b.finishedAt?.year == now.year).length
        : math.max(habit.booksFinished, books.where((b) => b.finishedAt != null).length);
    final figures = [
      _Figure(_duration(minutes), 'reading time'),
      _Figure('$cards', 'cards'),
      _Figure('$finished', finished == 1 ? 'book finished' : 'books finished'),
      _Figure('$readingDays', readingDays == 1 ? 'reading day' : 'reading days'),
      _Figure(readingDays == 0 ? '0' : '${(minutes / readingDays).round()}', 'minutes a reading day'),
      if (thisYear) _Figure('${habit.wpm.round()}', 'words a minute') else _Figure('${notebook.words.length}', 'words learned'),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      KitSegmented<bool>(values: const [true, false], selected: thisYear, label: (y) => y ? 'This year' : 'All time', onChanged: onChanged),
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
    if (m < 60) return '$m min';
    return m % 60 == 0 ? '${m ~/ 60} h' : '${m ~/ 60} h ${m % 60} min';
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
    ...ladder(streakMilestones, bestStreak, '🔥', (n) => '$n-day streak'),
    ...ladder(_bookMilestones, booksFinished, '📚', (n) => n == 1 ? 'First book' : '$n books'),
    ...ladder(_cardMilestones, cards, '🃏', (n) => '$n cards'),
    if (bestWeekMinutes >= 1) Trophy('⏱️', 'Best week: ${bestWeekMinutes.round()} min', earned: true),
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
        Text('Your first trophies are close.', style: kit.caption),
        const SizedBox(height: 12),
      ],
      Wrap(spacing: 10, runSpacing: 14, children: [
        for (final t in trophies)
          Semantics(
            container: true,
            label: t.earned ? 'Trophy: ${t.title}' : 'Next trophy: ${t.title}',
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
                    decoration: BoxDecoration(color: kit.field, shape: BoxShape.circle),
                    child: Text(t.emoji, style: const TextStyle(fontSize: 26)),
                  ),
                  const SizedBox(height: 6),
                  Text(t.earned ? t.title : 'Next: ${t.title}',
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
    if (books.isEmpty) return const KitEmpty(emoji: '📚', title: 'No books yet', message: 'Import a book from the Library.');
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
                semanticLabel: '${b.title}, ${(b.progress * 100).round()}% read',
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
        Text('Finished', style: kit.label),
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
/// ring once today's goal is done (like a story ring).
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
      decoration: BoxDecoration(shape: BoxShape.circle, color: kit.ink),
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
        painter: _ProgressRing(progress: b.progress.clamp(0.0, 1.0), color: kit.ink, track: kit.ink.withValues(alpha: 0.16)),
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
      return const KitEmpty(emoji: '🔖', title: 'No quotes yet', message: 'Save a card or highlight a line, and it shows up here.');
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

class _Heatmap extends StatelessWidget {
  const _Heatmap({required this.stats, required this.goal});
  final Map<String, DailyStat> stats;
  final GoalConfig goal;

  @override
  Widget build(BuildContext context) {
    final empty = Kit.of(context).field;
    final monday = parseDateKey(weekKey(DateTime.now()));
    final start = DateTime(monday.year, monday.month, monday.day - 7 * 11);
    return Semantics(
      label: 'Reading calendar for the last 12 weeks',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var w = 0; w < 12; w++)
            Column(children: [
              for (var d = 0; d < 7; d++)
                Builder(builder: (context) {
                  final day = DateTime(start.year, start.month, start.day + w * 7 + d);
                  final p = stats[dateKey(day)]?.progress(goal) ?? 0;
                  return Container(
                    margin: const EdgeInsets.all(1.5),
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: p == 0 ? empty : Color.lerp(Kit.of(context).ink.withValues(alpha: 0.2), Kit.of(context).ink, p),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
            ]),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- editing

/// Edit profile: photo or emoji, name, @username, pronouns, bio, genres.
Future<void> showEditProfile(BuildContext context) =>
    showKitSheet<void>(context, title: 'Edit profile', maxHeight: 0.94, builder: (_) => const _EditProfile());

/// Pronouns to pick from; anything else is "Custom".
const pronounChoices = ['he/him', 'she/her', 'they/them'];

/// Favourite genres shown on a profile.
const maxGenres = 3;

const _avatarEmoji = ['📚', '📖', '🦉', '🌙', '🌲', '☕', '🌊', '🌸', '🦊', '🐱', '🐼', '🦁', '🐢', '🌻', '🍵', '🎧', '✏️', '🧠', '🚀', '🌈', '🍂', '❄️', '🔥', '✨'];

class _EditProfile extends ConsumerStatefulWidget {
  const _EditProfile();

  @override
  ConsumerState<_EditProfile> createState() => _EditProfileState();
}

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
      title: 'Pick an emoji',
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
      setState(() => _error = 'Usernames are 3–24 letters, numbers, dots or underscores.');
      return;
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    final api = ref.read(apiProvider);
    if (api.enabled && username != _start.username) {
      // Claim the name first: it must be free on the server.
      try {
        await api.updateProfile(handle: username);
      } on ApiException catch (e) {
        if (e.status == 409 || e.status == 400) {
          if (mounted) {
            setState(() {
              _error = '@$username is taken. Try another.';
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
        KitChip(label: 'Photo', icon: Icons.photo_rounded, onTap: _pickPhoto),
        KitChip(label: 'Emoji', icon: Icons.emoji_emotions_rounded, onTap: _pickEmoji),
        if (_photo != null || _emoji.isNotEmpty)
          KitChip(
            label: 'Remove',
            icon: Icons.close_rounded,
            onTap: () => setState(() {
              _emoji = '';
              _photo = null;
            }),
          ),
      ]),
      label('NAME'),
      KitTextField(controller: _name, hint: 'Your name', capitalization: TextCapitalization.words, maxLength: 40, onChanged: (_) => setState(() {})),
      label('USERNAME'),
      KitTextField(controller: _username, hint: '@yourname', capitalization: TextCapitalization.none, maxLength: 25),
      label('PRONOUNS'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final p in [...pronounChoices, 'custom'])
          KitChip(
            label: p == 'custom' ? 'Custom' : p,
            selected: _pronounChoice == p,
            onTap: () => setState(() => _pronounChoice = _pronounChoice == p ? '' : p),
          ),
      ]),
      if (_pronounChoice == 'custom') ...[
        const SizedBox(height: 8),
        KitTextField(controller: _pronouns, hint: 'Your pronouns', capitalization: TextCapitalization.none, maxLength: 30),
      ],
      label('BIO'),
      KitTextField(controller: _bio, hint: 'What you love to read, and why', maxLines: 4, minLines: 2, maxLength: 150),
      label('FAVOURITE GENRES'),
      Text(
        _genres.length >= maxGenres ? 'Pick up to $maxGenres (that’s $maxGenres)' : 'Pick up to $maxGenres (${maxGenres - _genres.length} left)',
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
                label: g,
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
      KitButton(label: _saving ? 'Saving…' : 'Save', expand: true, onPressed: _saving ? null : _save),
    ]);
  }
}
