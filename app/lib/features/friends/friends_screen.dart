import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/habit/habit_engine.dart';
import '../../data/api_client.dart';
import '../../data/habit.dart';
import '../../data/settings_provider.dart';
import '../../data/sync_service.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

class FriendsData {
  const FriendsData({required this.me, required this.league, required this.board, required this.feed});
  final Map<String, dynamic> me;
  final Map<String, dynamic>? league;
  final List<Map<String, dynamic>> board;
  final List<Map<String, dynamic>> feed;
}

final friendsDataProvider = FutureProvider.autoDispose<FriendsData>((ref) async {
  final api = ref.read(apiProvider);
  // Upload pending reading first so the tables include today.
  await ref.read(syncServiceProvider).syncNow();
  final results = await Future.wait([api.me(), api.league(), api.friendsBoard(), api.feed()]);
  return FriendsData(
    me: results[0]! as Map<String, dynamic>,
    league: results[1] as Map<String, dynamic>?,
    board: results[2]! as List<Map<String, dynamic>>,
    feed: results[3]! as List<Map<String, dynamic>>,
  );
});

/// Friends tab (UX_DESIGN.md §5.7): weekly league of similar readers, friends
/// board, activity feed with kudos (no dislikes, no follower counts), invites.
class FriendsScreen extends ConsumerWidget {
  const FriendsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(apiProvider);
    final settings = ref.watch(settingsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Friends'),
        actions: [
          if (api.enabled)
            IconButton(tooltip: 'Add a friend', icon: const Icon(Icons.person_add_alt), onPressed: () => _addFriend(context, ref)),
        ],
      ),
      body: !api.enabled
          ? const _OfflineFriends()
          : RefreshIndicator(
              onRefresh: () => ref.refresh(friendsDataProvider.future),
              child: ref.watch(friendsDataProvider).when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => ListView(padding: const EdgeInsets.all(24), children: [
                      const SizedBox(height: 80),
                      const Icon(Icons.cloud_off, size: 48),
                      const SizedBox(height: 12),
                      const Text('Can’t reach BookReel right now. Your reading is saved and will sync later.', textAlign: TextAlign.center),
                      TextButton(onPressed: () => ref.invalidate(friendsDataProvider), child: const Text('Try again')),
                    ]),
                    data: (d) => ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
                      _InviteCard(code: d.me['invite_code'] as String, url: d.me['invite_url'] as String),
                      if (!settings.hideLeaderboards && d.league != null) ...[
                        const SizedBox(height: 16),
                        _LeagueCard(league: d.league!),
                      ],
                      if (!settings.hideLeaderboards) ...[
                        const SizedBox(height: 16),
                        _FriendsBoard(rows: d.board, onAdd: () => _addFriend(context, ref)),
                      ],
                      const SizedBox(height: 16),
                      _Feed(items: d.feed),
                    ]),
                  ),
            ),
    );
  }

  Future<void> _addFriend(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add a friend'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Their invite code', hintText: 'e.g. 7PA756JQ'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Add')),
        ],
      ),
    );
    if (code == null || code.isEmpty || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final name = await ref.read(apiProvider).addFriend(code);
      messenger.showSnackBar(SnackBar(content: Text(name == null ? 'No reader found with that code.' : 'You and $name are now friends 🎉')));
      if (name != null) ref.invalidate(friendsDataProvider);
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Couldn’t add friend. Check your connection.')));
    }
  }
}

class _InviteCard extends StatelessWidget {
  const _InviteCard({required this.code, required this.url});
  final String code;
  final String url;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Read with friends', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text('Share your code. Friends keep each other going.'),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: Semantics(
                label: 'Your invite code $code',
                child: Text(code, style: theme.textTheme.headlineSmall?.copyWith(letterSpacing: 4, fontWeight: FontWeight.w700)),
              ),
            ),
            IconButton(
              tooltip: 'Copy code',
              icon: const Icon(Icons.copy),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: code));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code copied')));
              },
            ),
            FilledButton.icon(
              onPressed: () => SharePlus.instance.share(ShareParams(
                text: 'Read with me on BookReel: books as bite-sized cards. Add me with code $code\n$url',
              )),
              icon: const Icon(Icons.ios_share),
              label: const Text('Invite'),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _LeagueCard extends StatelessWidget {
  const _LeagueCard({required this.league});
  final Map<String, dynamic> league;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = (league['rows'] as List).cast<Map<String, dynamic>>();
    final promote = league['promote'] as int;
    final demote = league['demote'] as int;
    final size = rows.length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.emoji_events_outlined, color: ember),
            const SizedBox(width: 8),
            Text('${league['division']} league', style: theme.textTheme.titleMedium),
            const Spacer(),
            Text('This week', style: theme.textTheme.bodySmall),
          ]),
          const SizedBox(height: 4),
          Text('Ranked by days you hit your goal, then minutes read. Top $promote move up.', style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          for (final r in rows.take(10))
            _RankRow(
              rank: r['rank'] as int,
              name: r['name'] as String,
              me: r['me'] == true,
              detail: '${r['activeDays']} days · ${r['minutes']} min',
              zone: (r['rank'] as int) <= promote && (r['score'] as int) > 0
                  ? _Zone.up
                  : (size >= promote + demote && (r['rank'] as int) > size - demote)
                      ? _Zone.down
                      : _Zone.none,
            ),
          if (rows.length > 10 && !rows.take(10).any((r) => r['me'] == true))
            for (final r in rows.where((r) => r['me'] == true))
              _RankRow(rank: r['rank'] as int, name: r['name'] as String, me: true, detail: '${r['activeDays']} days · ${r['minutes']} min', zone: _Zone.none),
        ]),
      ),
    );
  }
}

enum _Zone { up, down, none }

class _RankRow extends StatelessWidget {
  const _RankRow({required this.rank, required this.name, required this.me, required this.detail, required this.zone});
  final int rank;
  final String name;
  final bool me;
  final String detail;
  final _Zone zone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: me ? theme.colorScheme.secondaryContainer : null,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        SizedBox(width: 28, child: Text('$rank', style: theme.textTheme.titleSmall)),
        Expanded(child: Text(me ? '$name (you)' : name, overflow: TextOverflow.ellipsis)),
        Text(detail, style: theme.textTheme.bodySmall),
        const SizedBox(width: 6),
        // Neutral colours: moving down is shown, never shamed (UX_DESIGN.md §6.2).
        Icon(
          switch (zone) { _Zone.up => Icons.arrow_upward, _Zone.down => Icons.arrow_downward, _Zone.none => Icons.remove },
          size: 16,
          color: zone == _Zone.up ? ember : theme.colorScheme.onSurfaceVariant.withValues(alpha: zone == _Zone.none ? 0.3 : 1),
        ),
      ]),
    );
  }
}

class _FriendsBoard extends StatelessWidget {
  const _FriendsBoard({required this.rows, required this.onAdd});
  final List<Map<String, dynamic>> rows;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Friends this week', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (rows.length <= 1)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.group_add_outlined),
              title: const Text('No friends yet'),
              subtitle: const Text('Add a friend with their invite code'),
              onTap: onAdd,
            )
          else
            for (var i = 0; i < rows.length; i++)
              _RankRow(
                rank: i + 1,
                name: rows[i]['name'] as String,
                me: rows[i]['me'] == true,
                detail: '${rows[i]['activeDays']} days · ${rows[i]['minutes']} min',
                zone: _Zone.none,
              ),
        ]),
      ),
    );
  }
}

class _Feed extends ConsumerStatefulWidget {
  const _Feed({required this.items});
  final List<Map<String, dynamic>> items;

  @override
  ConsumerState<_Feed> createState() => _FeedState();
}

class _FeedState extends ConsumerState<_Feed> {
  final Set<String> _given = {};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Activity', style: theme.textTheme.titleMedium),
          if (widget.items.isEmpty)
            const Padding(padding: EdgeInsets.only(top: 8), child: Text('When you or your friends hit a goal or finish a book, it shows up here.')),
          for (final item in widget.items)
            Builder(builder: (context) {
              final id = item['id'] as String;
              final gave = item['gaveKudos'] == true || _given.contains(id);
              final count = (item['kudos'] as int) + (_given.contains(id) && item['gaveKudos'] != true ? 1 : 0);
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Text(
                  switch (item['type']) { 'book_finished' => '📚', 'streak_milestone' => '🔥', _ => '✅' },
                  style: const TextStyle(fontSize: 24),
                ),
                title: Text(item['text'] as String),
                subtitle: Text(_ago(DateTime.parse(item['at'] as String))),
                trailing: item['mine'] == true
                    ? (count > 0 ? Text('👏 $count') : null)
                    : TextButton(
                        onPressed: gave
                            ? null
                            : () async {
                                HapticFeedback.lightImpact();
                                setState(() => _given.add(id));
                                try {
                                  await ref.read(apiProvider).kudos(id);
                                } catch (_) {
                                  if (mounted) setState(() => _given.remove(id));
                                }
                              },
                        child: Text(count > 0 ? '👏 $count' : '👏 Kudos'),
                      ),
              );
            }),
        ]),
      ),
    );
  }

  String _ago(DateTime at) {
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }
}

/// Shown when no server is configured: the reader's own week and an invite.
class _OfflineFriends extends ConsumerWidget {
  const _OfflineFriends();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);
    final habit = ref.watch(habitProvider);
    final notifier = ref.read(habitProvider.notifier);
    final monday = parseDateKey(weekKey(DateTime.now()));
    final week = [
      for (var d = 0; d < 7; d++) habit.stats[dateKey(DateTime(monday.year, monday.month, monday.day + d))] ?? const DailyStat(),
    ];
    return ListView(padding: const EdgeInsets.all(16), children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Your week', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              for (var d = 0; d < 7; d++)
                Column(children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: week[d].meets(settings.goal) ? ember : theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('MTWTFSS'[d], style: theme.textTheme.bodySmall),
                ]),
            ]),
            const SizedBox(height: 12),
            StreakBadge(days: notifier.displayStreak(), weekly: settings.goalMode == GoalMode.weekly),
          ]),
        ),
      ),
      const SizedBox(height: 16),
      const Card(
        child: ListTile(
          contentPadding: EdgeInsets.all(16),
          leading: Icon(Icons.cloud_off_outlined),
          title: Text('Friends and leagues need the BookReel server'),
          subtitle: Text('This build runs offline. Everything you read still counts toward your streak.'),
        ),
      ),
    ]);
  }
}
