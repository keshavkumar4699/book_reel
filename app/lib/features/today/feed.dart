import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/book.dart';
import '../../data/api_client.dart';
import '../../data/library.dart';
import '../../data/sessions.dart';
import '../../data/settings_provider.dart';
import '../../data/sync_service.dart';
import '../../services/mood.dart';
import '../../ui/kit.dart';
import '../../ui/widgets.dart';
import '../profile/profile_screen.dart' show ReaderAvatar;
import '../social/profile_header.dart' show PersonAvatar;

/// One card in the Today feed (Cloro plan §10): a reading session or a
/// milestone, yours or from a reader you follow.
class FeedEntry {
  const FeedEntry({
    required this.id,
    required this.type,
    required this.at,
    required this.userId,
    required this.name,
    this.handle,
    this.avatar = '',
    required this.mine,
    this.text = '',
    this.data = const {},
    this.kudos = 0,
    this.gaveKudos = false,
    this.comments = 0,
    this.local = false,
  });

  factory FeedEntry.fromServer(Map<String, dynamic> j) {
    final author = (j['author'] as Map?)?.cast<String, dynamic>() ?? const {};
    return FeedEntry(
      id: j['id'] as String,
      type: j['type'] as String,
      at: DateTime.tryParse('${j['at']}')?.toLocal() ?? DateTime.now(),
      userId: '${j['userId'] ?? ''}',
      name: '${author['name'] ?? 'Reader'}',
      handle: author['handle'] as String?,
      avatar: '${author['avatar'] ?? ''}',
      mine: j['mine'] == true,
      text: '${j['text'] ?? ''}',
      data: (j['data'] as Map?)?.cast<String, dynamic>() ?? const {},
      kudos: (j['kudos'] as num?)?.toInt() ?? 0,
      gaveKudos: j['gaveKudos'] == true,
      comments: (j['comments'] as num?)?.toInt() ?? 0,
    );
  }

  /// Your own session from the phone's log (offline, or not uploaded yet).
  factory FeedEntry.fromSession(ReadingSession s, String name) => FeedEntry(
        id: 'local:${s.id}',
        type: 'session',
        at: s.startedAt,
        userId: 'me',
        name: name,
        mine: true,
        data: {
          'book': {'title': s.title, 'author': s.author},
          'minutes': s.minutes,
          'cards': s.cards,
          'progress': s.progress,
          'mood': ?s.mood,
          'quote': ?s.quote,
        },
        local: true,
      );

  final String id;

  /// session, book_finished, streak_milestone, best_week…
  final String type;
  final DateTime at;
  final String userId;
  final String name;
  final String? handle;
  final String avatar;
  final bool mine;
  final String text;
  final Map<String, dynamic> data;
  final int kudos;
  final bool gaveKudos;
  final int comments;

  /// Only on this phone: no kudos or comments.
  final bool local;

  FeedEntry copyWith({int? kudos, bool? gaveKudos, int? comments}) => FeedEntry(
        id: id,
        type: type,
        at: at,
        userId: userId,
        name: name,
        handle: handle,
        avatar: avatar,
        mine: mine,
        text: text,
        data: data,
        kudos: kudos ?? this.kudos,
        gaveKudos: gaveKudos ?? this.gaveKudos,
        comments: comments ?? this.comments,
        local: local,
      );
}

class FeedPage {
  const FeedPage(this.items, {this.more = false});
  final List<FeedEntry> items;

  /// The server may have older items.
  final bool more;
}

/// The Today feed: from the server (your sessions and milestones and those of
/// readers you follow, newest first, 20 at a time), or offline your own
/// sessions from the phone.
class TodayFeed extends AsyncNotifier<FeedPage> {
  static const pageSize = 20;
  bool _loadingMore = false;

  @override
  Future<FeedPage> build() async {
    final api = ref.read(apiProvider);
    if (!api.enabled) return FeedPage(_local());
    // Upload your latest sessions first, so the feed has them.
    await ref.read(syncServiceProvider).syncNow();
    final items = await api.feed();
    return FeedPage([for (final j in items) if (j['type'] != 'goal_met') FeedEntry.fromServer(j)], more: items.length >= pageSize);
  }

  List<FeedEntry> _local() {
    final name = ref.read(settingsProvider).displayName;
    final sessions = ref.read(sessionLogProvider);
    return [
      for (final s in sessions.reversed)
        if (s.worthSharing) FeedEntry.fromSession(s, name),
    ];
  }

  /// The next page, when the end of the list comes into view.
  Future<void> loadMore() async {
    final page = state.value;
    if (_loadingMore || page == null || !page.more || page.items.isEmpty) return;
    _loadingMore = true;
    try {
      final before = page.items.where((e) => !e.local).lastOrNull?.at.toUtc().toIso8601String();
      final items = await ref.read(apiProvider).feed(before: before);
      final seen = {for (final e in page.items) e.id};
      state = AsyncData(FeedPage([
        ...page.items,
        for (final j in items)
          if (j['type'] != 'goal_met' && !seen.contains(j['id'])) FeedEntry.fromServer(j),
      ], more: items.length >= pageSize));
    } catch (_) {
      // Offline for a moment: try again on the next scroll.
    } finally {
      _loadingMore = false;
    }
  }

  void _replace(String id, FeedEntry Function(FeedEntry e) change) {
    final page = state.value;
    if (page == null) return;
    state = AsyncData(FeedPage([for (final e in page.items) e.id == id ? change(e) : e], more: page.more));
  }

  /// Kudos (no dislikes, and not on your own): shown at once, undone if the
  /// server says no.
  Future<bool> giveKudos(FeedEntry e) async {
    if (e.mine || e.gaveKudos || e.local) return false;
    _replace(e.id, (x) => x.copyWith(kudos: x.kudos + 1, gaveKudos: true));
    try {
      await ref.read(apiProvider).kudos(e.id);
      return true;
    } catch (_) {
      _replace(e.id, (x) => x.copyWith(kudos: x.kudos - 1, gaveKudos: false));
      return false;
    }
  }

  void setComments(String id, int count) => _replace(id, (x) => x.copyWith(comments: count));
}

final todayFeedProvider = AsyncNotifierProvider.autoDispose<TodayFeed, FeedPage>(TodayFeed.new);

/// "now", "5 min", "3 h", "Yesterday", "Tue", "12 Nov".
String timeAgo(DateTime at, DateTime now) {
  final d = now.difference(at);
  if (d.inMinutes < 1) return 'now';
  if (d.inMinutes < 60) return '${d.inMinutes} min';
  if (d.inHours < 24 && at.day == now.day) return '${d.inHours} h';
  final day = DateTime(at.year, at.month, at.day);
  final today = DateTime(now.year, now.month, now.day);
  final days = today.difference(day).inDays;
  if (days == 1) return 'Yesterday';
  if (days < 7) return const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][at.weekday - 1];
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${at.day} ${months[at.month - 1]}${at.year == now.year ? '' : ' ${at.year}'}';
}

String _minutes(num m) => m < 1 ? '<1' : m.round().toString();

/// One activity, flat (no box): who and when, what they read with the
/// stats, the line they saved, then kudos and comments.
class ActivityCard extends ConsumerWidget {
  const ActivityCard({super.key, required this.entry, this.now});

  final FeedEntry entry;

  /// For tests.
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kit = Kit.of(context);
    final e = entry;
    final settings = ref.watch(settingsProvider);
    final book = (e.data['book'] as Map?)?.cast<String, dynamic>();
    final title = '${book?['title'] ?? ''}';
    // Your own book's cover, when it's on this phone.
    final BookMeta? cover = e.mine && title.isNotEmpty
        ? ref.watch(libraryProvider).where((b) => b.title == title).firstOrNull
        : null;
    void openAuthor() => e.mine ? context.go('/profile') : context.push('/u/${Uri.encodeComponent(e.userId)}');

    final header = Row(children: [
      GestureDetector(
        onTap: openAuthor,
        child: e.mine ? ReaderAvatar(settings: settings, size: 40) : PersonAvatar(name: e.name, emoji: e.avatar, size: 40),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: openAuthor,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(e.mine ? 'You' : e.name, style: kit.strong, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(timeAgo(e.at, now ?? DateTime.now()), style: kit.caption),
          ]),
        ),
      ),
    ]);

    final Widget body;
    if (e.type == 'session') {
      final mood = Mood.byName(e.data['mood'] as String?);
      final quote = e.data['quote'] as String?;
      final progress = (e.data['progress'] as num?)?.toDouble() ?? 0;
      Widget stat(String value, String label) => Padding(
            padding: const EdgeInsets.only(right: 22),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: kit.caption),
              Text(value, style: kit.strong.copyWith(fontSize: 17)),
            ]),
          );
      body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title.isEmpty ? 'Read' : title, style: kit.heading, maxLines: 2, overflow: TextOverflow.ellipsis),
              if ('${book?['author'] ?? ''}'.isNotEmpty) Text('${book!['author']}', style: kit.caption),
            ]),
          ),
          if (cover != null) ...[const SizedBox(width: 12), BookCover(book: cover, width: 40)],
        ]),
        const SizedBox(height: 12),
        Wrap(runSpacing: 8, children: [
          stat('${_minutes((e.data['minutes'] as num?) ?? 0)} min', 'Time'),
          stat('${e.data['cards'] ?? 0}', 'Cards'),
          if (progress > 0) stat('${(progress * 100).round()}%', 'Book'),
          if (mood != null) stat('${mood.emoji} ${mood.label}', 'Mood'),
        ]),
        if (quote != null && quote.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.only(left: 12),
            decoration: BoxDecoration(border: Border(left: BorderSide(color: kit.ink.withValues(alpha: 0.35), width: 2))),
            child: Text('“$quote”', style: kit.body.copyWith(fontStyle: FontStyle.italic)),
          ),
        ],
      ]);
    } else {
      final emoji = switch (e.type) { 'book_finished' => '📚', 'streak_milestone' => '🔥', 'best_week' => '🏆', _ => '✨' };
      // The server's line starts with the reader's name; the header says it already.
      var line = e.text.startsWith('${e.name} ') ? e.text.substring(e.name.length + 1) : e.text;
      // …and ends with the same emoji the card shows.
      if (line.endsWith(' $emoji')) line = line.substring(0, line.length - emoji.length - 1);
      body = Row(children: [
        Text(emoji, style: const TextStyle(fontSize: 26)),
        const SizedBox(width: 12),
        Expanded(child: Text(line.isEmpty ? e.text : '${line[0].toUpperCase()}${line.substring(1)}', style: kit.heading)),
      ]);
    }

    final actions = e.local
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              KitPressable(
                onTap: e.mine || e.gaveKudos
                    ? null
                    : () async {
                        HapticFeedback.lightImpact();
                        if (!await ref.read(todayFeedProvider.notifier).giveKudos(e) && context.mounted) {
                          showKitToast(context, 'Couldn’t send kudos. Check your connection.', icon: Icons.cloud_off_rounded);
                        }
                      },
                semanticLabel: e.mine ? '${e.kudos} kudos' : (e.gaveKudos ? 'You gave kudos, ${e.kudos} in all' : 'Give kudos, ${e.kudos} so far'),
                excludeSemantics: true,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 8, 18, 8),
                  child: Text('👏 ${e.kudos}', style: kit.strong.copyWith(color: e.gaveKudos ? kit.ink : kit.inkSoft)),
                ),
              ),
              KitPressable(
                onTap: () => showComments(context, ref, e),
                semanticLabel: '${e.comments} comment${e.comments == 1 ? '' : 's'}. Open',
                excludeSemantics: true,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 8, 18, 8),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.chat_bubble_outline_rounded, size: 19, color: kit.inkSoft),
                    const SizedBox(width: 6),
                    Text('${e.comments}', style: kit.strong.copyWith(color: kit.inkSoft)),
                  ]),
                ),
              ),
            ]),
          );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        header,
        const SizedBox(height: 12),
        body,
        actions,
      ]),
    );
  }
}

/// Comments on an activity: read them, add one, remove yours (or any on
/// your own activity).
Future<void> showComments(BuildContext context, WidgetRef ref, FeedEntry e) => showKitSheet<void>(
      context,
      title: 'Comments',
      subtitle: e.type == 'session' ? '${e.mine ? 'You' : e.name} · ${(e.data['book'] as Map?)?['title'] ?? ''}' : null,
      builder: (_) => _Comments(entry: e),
    );

class _Comments extends ConsumerStatefulWidget {
  const _Comments({required this.entry});
  final FeedEntry entry;

  @override
  ConsumerState<_Comments> createState() => _CommentsState();
}

class _CommentsState extends ConsumerState<_Comments> {
  List<Map<String, dynamic>>? _items;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await ref.read(apiProvider).comments(widget.entry.id);
      if (!mounted) return;
      setState(() {
        _items = items;
        _failed = false;
      });
      ref.read(todayFeedProvider.notifier).setComments(widget.entry.id, items.length);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _write() async {
    final text = await showKitPrompt(context, title: 'Add a comment', hint: 'Say something kind', maxLines: 4, confirm: 'Post');
    if (text == null || text.trim().isEmpty || !mounted) return;
    try {
      await ref.read(apiProvider).addComment(widget.entry.id, text.trim());
      await _load();
    } catch (_) {
      if (mounted) showKitToast(context, 'Couldn’t post your comment. Check your connection.', icon: Icons.cloud_off_rounded);
    }
  }

  Future<void> _delete(Map<String, dynamic> c) async {
    try {
      await ref.read(apiProvider).deleteComment(c['id'] as String);
      await _load();
    } catch (_) {
      if (mounted) showKitToast(context, 'Couldn’t remove it. Check your connection.', icon: Icons.cloud_off_rounded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    final items = _items;
    final now = DateTime.now();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (_failed)
        Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Text('Couldn’t load comments.', style: kit.caption))
      else if (items == null)
        const Padding(padding: EdgeInsets.all(24), child: Center(child: KitSpinner()))
      else if (items.isEmpty)
        Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Text('No comments yet. Be the first.', style: kit.caption))
      else
        for (final c in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              PersonAvatar(name: '${c['name']}', emoji: '${c['avatar'] ?? ''}', size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text.rich(TextSpan(children: [
                    TextSpan(text: c['mine'] == true ? 'You' : '${c['name']}', style: kit.strong),
                    TextSpan(text: '  ${timeAgo(DateTime.tryParse('${c['at']}')?.toLocal() ?? now, now)}', style: kit.caption),
                  ])),
                  const SizedBox(height: 2),
                  Text('${c['text']}', style: kit.body),
                ]),
              ),
              if (c['can_delete'] == true)
                KitIconButton(icon: Icons.delete_outline_rounded, semanticLabel: 'Remove comment', onPressed: () => _delete(c)),
            ]),
          ),
      KitGroup(divided: true, children: [
        KitRow(icon: Icons.edit_rounded, title: 'Add a comment', chevron: false, onTap: _write),
      ]),
    ]);
  }
}

/// Loads the next page once the end of the feed comes into view.
class FeedLoadMore extends ConsumerStatefulWidget {
  const FeedLoadMore({super.key});

  @override
  ConsumerState<FeedLoadMore> createState() => _FeedLoadMoreState();
}

class _FeedLoadMoreState extends ConsumerState<FeedLoadMore> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(todayFeedProvider.notifier).loadMore();
    });
  }

  @override
  Widget build(BuildContext context) => const Padding(padding: EdgeInsets.all(20), child: Center(child: KitSpinner()));
}
