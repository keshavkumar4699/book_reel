import 'dart:async';
import 'dart:io';

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

/// The reader's profile, Instagram style (UX_DESIGN.md Revision 7): avatar,
/// a few numbers, name, @username, pronouns and bio; a shelf of books; and
/// tabs for saved quotes, books and reading stats. Progress shows growth,
/// not just totals (§5.8); nothing here is ranked against anyone.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

enum _Tab { quotes, books, stats }

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  _Tab _tab = _Tab.quotes;

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    final s = ref.watch(settingsProvider);
    final habit = ref.watch(habitProvider);
    final notebook = ref.watch(notebookProvider);
    final books = ref.watch(libraryProvider);
    final notifier = ref.read(habitProvider.notifier);
    final streak = notifier.displayStreak();
    final goalMet = habit.today(DateTime.now()).meets(s.goal);
    final reading = ref.read(libraryProvider.notifier).current;
    final saved = notebook.saved.length + notebook.highlights.length;

    Widget stat(String value, String label, VoidCallback? onTap) => Expanded(
          child: KitPressable(
            onTap: onTap,
            semanticLabel: '$value $label',
            excludeSemantics: true,
            child: Column(children: [
              Text(value, style: kit.title.copyWith(fontSize: 20)),
              Text(label, style: kit.caption.copyWith(fontSize: 12.5)),
            ]),
          ),
        );

    return KitPage(
      title: s.username.isEmpty ? s.displayName : '@${s.username}',
      actions: [
        KitIconButton(icon: Icons.settings_rounded, semanticLabel: 'Settings', onPressed: () => context.push('/settings')),
      ],
      children: [
        // Avatar and numbers.
        Row(children: [
          KitPressable(
            onTap: () => showEditProfile(context),
            semanticLabel: 'Profile photo. Edit profile',
            excludeSemantics: true,
            child: ReaderAvatar(settings: s, size: 88, ring: goalMet),
          ),
          const SizedBox(width: 12),
          stat('${habit.booksFinished}', 'books', () => setState(() => _tab = _Tab.books)),
          stat('$streak', s.goalMode == GoalMode.weekly ? 'week streak' : 'day streak', () => setState(() => _tab = _Tab.stats)),
          stat('$saved', 'saved', () => setState(() => _tab = _Tab.quotes)),
        ]),
        const SizedBox(height: 14),
        // Name, pronouns, username, bio.
        Text.rich(
          TextSpan(children: [
            TextSpan(text: s.displayName, style: kit.strong),
            if (s.pronouns.isNotEmpty) TextSpan(text: '  ${s.pronouns}', style: kit.caption),
          ]),
        ),
        const SizedBox(height: 4),
        if (s.bio.isNotEmpty)
          Text(s.bio, style: kit.body)
        else
          KitPressable(
            onTap: () => showEditProfile(context),
            child: Text('Add a bio: what you love to read, and why', style: kit.body.copyWith(color: kit.accent)),
          ),
        if (reading != null) ...[
          const SizedBox(height: 6),
          KitPressable(
            onTap: () => context.push('/read/${reading.id}'),
            child: Text.rich(TextSpan(children: [
              TextSpan(text: '📖 Reading ', style: kit.caption),
              TextSpan(text: reading.title, style: kit.caption.copyWith(color: kit.accent, fontWeight: FontWeight.w800)),
            ])),
          ),
        ],
        if (s.interests.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final g in s.interests)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: kit.field, borderRadius: BorderRadius.circular(12), border: Border.all(color: kit.stroke)),
                child: Text(g, style: kit.caption.copyWith(fontSize: 12.5, color: kit.ink)),
              ),
          ]),
        ],
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: KitButton.secondary(label: 'Edit profile', compact: true, expand: true, onPressed: () => showEditProfile(context))),
          const SizedBox(width: 8),
          Expanded(
            child: KitButton.secondary(
              label: 'Share profile',
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
          ),
          const SizedBox(width: 4),
          KitIconButton(
            icon: Icons.person_add_alt_1_rounded,
            semanticLabel: 'Find friends',
            onPressed: () => context.go('/friends'),
            size: 40,
          ),
        ]),
        // The shelf: every book as a circle with its progress around it.
        if (books.isNotEmpty) ...[
          const SizedBox(height: 18),
          SizedBox(
            height: 102,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: books.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (context, i) {
                final b = books[i];
                return KitPressable(
                  onTap: () => context.push('/read/${b.id}'),
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
        ],
        const SizedBox(height: 16),
        KitSegmented<_Tab>(
          values: _Tab.values,
          selected: _tab,
          label: (t) => switch (t) {
            _Tab.quotes => 'Quotes',
            _Tab.books => 'Books',
            _Tab.stats => 'Stats',
          },
          onChanged: (t) => setState(() => _tab = t),
        ),
        const SizedBox(height: 12),
        switch (_tab) {
          _Tab.quotes => _QuotesGrid(notebook: notebook),
          _Tab.books => _BooksList(),
          _Tab.stats => _Stats(habit: habit, notebook: notebook, settings: s, streak: streak),
        },
      ],
    );
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
        decoration: BoxDecoration(gradient: LinearGradient(colors: [kit.accent, Color.lerp(kit.accent, kit.base, 0.55)!])),
        child: Center(
          child: Text(name.isEmpty || name == 'Reader' ? '📖' : name.characters.first.toUpperCase(),
              style: kit.title.copyWith(color: kit.onAccent, fontSize: size * 0.42)),
        ),
      );
    }
    final avatar = ClipOval(child: SizedBox(width: size, height: size, child: inner));
    if (!ring) return avatar;
    return Container(
      padding: EdgeInsets.all(size * 0.04),
      decoration: const BoxDecoration(shape: BoxShape.circle, gradient: SweepGradient(colors: [ember, Color(0xFFFFD27A), ember])),
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
        painter: _ProgressRing(progress: b.progress.clamp(0.0, 1.0), color: kit.accent, track: kit.ink.withValues(alpha: 0.16)),
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
      for (final s in notebook.saved) (at: s.createdAt, text: s.text, link: '/read/${s.bookId}?sid=${s.startSid}', tint: kit.accent, saved: true),
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
            onTap: () => context.push(q.link),
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

class _BooksList extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final books = ref.watch(libraryProvider);
    if (books.isEmpty) return const KitEmpty(emoji: '📚', title: 'No books yet', message: 'Import a book from the Library.');
    return KitGroup(children: [
      for (final b in books)
        KitRow(
          leading: ClipRRect(borderRadius: BorderRadius.circular(4), child: BookCover(book: b, width: 38)),
          title: b.title,
          subtitle: b.finishedAt != null ? '${b.author} · Finished ✓' : '${b.author} · ${(b.progress * 100).round()}%',
          onTap: () => context.push('/read/${b.id}'),
        ),
    ]);
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.habit, required this.notebook, required this.settings, required this.streak});
  final HabitState habit;
  final NotebookState notebook;
  final AppSettings settings;
  final int streak;

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    final tiles = [
      ('🔥', '$streak', 'current streak'),
      ('🏆', '${habit.streak.best}', 'best streak'),
      ('📚', '${habit.booksFinished}', 'books finished'),
      ('🃏', '${habit.totalVerifiedCards}', 'cards read'),
      ('⏱️', '${habit.totalMinutes.round()}', 'minutes'),
      ('⚡', '${habit.wpm.round()}', 'words / min'),
      ('🔤', '${notebook.words.length}', 'words learned'),
      ('✏️', '${notebook.highlights.length}', 'highlights'),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 2.1,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        children: [
          for (final t in tiles)
            KitPanel(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Text(t.$1, style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(t.$2, style: kit.title.copyWith(fontSize: 20)),
                    Text(t.$3, style: kit.caption.copyWith(fontSize: 12.5), overflow: TextOverflow.ellipsis),
                  ]),
                ),
              ]),
            ),
        ],
      ),
      const SizedBox(height: 22),
      Text('LAST 12 WEEKS', style: kit.label),
      const SizedBox(height: 10),
      KitPanel(padding: const EdgeInsets.all(10), child: _Heatmap(stats: habit.stats, goal: settings.goal)),
    ]);
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
                      color: p == 0 ? empty : Color.lerp(ember.withValues(alpha: 0.25), ember, p),
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
  late final _pronouns = TextEditingController(text: _start.pronouns);
  late final _bio = TextEditingController(text: _start.bio);
  late Set<String> _genres = {..._start.interests};
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
    final file = files.first;
    final bytes = await file.readAsBytes();
    final dir = await getApplicationDocumentsDirectory();
    final dot = file.name.lastIndexOf('.');
    final ext = dot < 0 ? 'jpg' : file.name.substring(dot + 1).toLowerCase();
    // A new name each time, so no cached copy of an older photo shows.
    final out = File('${dir.path}/avatar_${DateTime.now().millisecondsSinceEpoch}.$ext');
    await out.writeAsBytes(bytes);
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
          pronouns: _pronouns.text.trim(),
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
      KitTextField(controller: _pronouns, hint: 'she/her, he/him, they/them…', capitalization: TextCapitalization.none, maxLength: 30),
      label('BIO'),
      KitTextField(controller: _bio, hint: 'What you love to read, and why', maxLines: 4, minLines: 2, maxLength: 150),
      label('FAVOURITE GENRES'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final g in readingGenres)
          KitChip(
            label: g,
            selected: _genres.contains(g),
            onTap: () => setState(() => _genres = _genres.contains(g) ? ({..._genres}..remove(g)) : {..._genres, g}),
          ),
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
