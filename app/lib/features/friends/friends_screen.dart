import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/habit/habit_engine.dart';
import '../../data/api_client.dart';
import '../../data/habit.dart';
import '../../data/settings_provider.dart';
import '../../data/sync_service.dart';
import '../../ui/kit.dart';
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
    final kit = Kit.of(context);
    final List<Widget> children = !api.enabled
        ? const [_OfflineFriends()]
        : ref.watch(friendsDataProvider).when(
              loading: () => const [Padding(padding: EdgeInsets.all(60), child: Center(child: KitSpinner()))],
              error: (e, _) => [
                KitEmpty(
                  emoji: '☁️',
                  title: 'Can’t reach Cloro right now',
                  message: 'Your reading is saved and will sync later.',
                  action: KitButton.secondary(label: 'Try again', onPressed: () => ref.invalidate(friendsDataProvider)),
                ),
              ],
              data: (d) => [
                _InviteCard(code: d.me['invite_code'] as String, url: d.me['invite_url'] as String),
                if (!settings.hideLeaderboards && d.league != null) ...[
                  const SizedBox(height: 14),
                  _LeagueCard(league: d.league!),
                ],
                if (!settings.hideLeaderboards) ...[
                  const SizedBox(height: 14),
                  _FriendsBoard(rows: d.board, onAdd: () => _addFriend(context, ref)),
                ],
                const SizedBox(height: 14),
                _Feed(items: d.feed),
              ],
            );
    return KitPage(
      back: false,
      backdrop: false,
      dock: true,
      title: 'Friends',
      onRefresh: api.enabled ? () => ref.refresh(friendsDataProvider.future) : null,
      actions: [
        if (api.enabled)
          KitIconButton(icon: Icons.person_add_alt_1_rounded, semanticLabel: 'Add a friend', onPressed: () => _addFriend(context, ref)),
      ],
      children: [DefaultTextStyle(style: kit.body, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children))],
    );
  }

  Future<void> _addFriend(BuildContext context, WidgetRef ref) async {
    final code = await showKitPrompt(
      context,
      title: 'Add a friend',
      message: 'Enter their invite code',
      hint: 'e.g. 7PA756JQ',
      confirm: 'Add',
      capitalization: TextCapitalization.characters,
    );
    if (code == null || code.isEmpty || !context.mounted) return;
    try {
      final name = await ref.read(apiProvider).addFriend(code);
      if (!context.mounted) return;
      showKitToast(context, name == null ? 'No reader found with that code.' : 'You and $name are now friends 🎉');
      if (name != null) ref.invalidate(friendsDataProvider);
    } catch (_) {
      if (context.mounted) showKitToast(context, 'Couldn’t add friend. Check your connection.', icon: Icons.cloud_off_rounded);
    }
  }
}

class _InviteCard extends StatelessWidget {
  const _InviteCard({required this.code, required this.url});
  final String code;
  final String url;

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    return KitPanel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Read with friends', style: kit.heading),
        const SizedBox(height: 2),
        Text('Share your code. Friends keep each other going.', style: kit.caption),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: Semantics(
              label: 'Your invite code $code',
              child: Text(code, style: kit.title.copyWith(letterSpacing: 3)),
            ),
          ),
          KitIconButton(
            icon: Icons.copy_rounded,
            semanticLabel: 'Copy code',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              showKitToast(context, 'Code copied', icon: Icons.check_rounded);
            },
          ),
          const SizedBox(width: 6),
          KitButton(
            label: 'Invite',
            leading: const ShareArrowIcon(),
            compact: true,
            onPressed: () => SharePlus.instance.share(ShareParams(
              text: 'Read with me on Cloro: books as bite-sized cards. Add me with code $code\n$url',
            )),
          ),
        ]),
      ]),
    );
  }
}

class _LeagueCard extends StatelessWidget {
  const _LeagueCard({required this.league});
  final Map<String, dynamic> league;

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    final rows = (league['rows'] as List).cast<Map<String, dynamic>>();
    final promote = league['promote'] as int;
    final demote = league['demote'] as int;
    final size = rows.length;
    return KitPanel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.emoji_events_rounded, color: ember),
          const SizedBox(width: 8),
          Text('${league['division']} league', style: kit.heading),
          const Spacer(),
          Text('This week', style: kit.caption),
        ]),
        const SizedBox(height: 4),
        Text('Ranked by days you hit your goal, then minutes read. Top $promote move up.', style: kit.caption),
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
    final kit = Kit.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: me ? kit.accent.withValues(alpha: 0.16) : null,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        SizedBox(width: 28, child: Text('$rank', style: kit.strong)),
        Expanded(child: Text(me ? '$name (you)' : name, overflow: TextOverflow.ellipsis, style: kit.body)),
        Text(detail, style: kit.caption),
        const SizedBox(width: 6),
        // Neutral colours: moving down is shown, never shamed (UX_DESIGN.md §6.2).
        Icon(
          switch (zone) { _Zone.up => Icons.arrow_upward_rounded, _Zone.down => Icons.arrow_downward_rounded, _Zone.none => Icons.remove_rounded },
          size: 16,
          color: zone == _Zone.up ? ember : kit.inkSoft.withValues(alpha: zone == _Zone.none ? 0.3 : 1),
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
    final kit = Kit.of(context);
    return KitPanel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Friends this week', style: kit.heading),
        const SizedBox(height: 8),
        if (rows.length <= 1)
          KitRow(icon: Icons.group_add_rounded, title: 'No friends yet', subtitle: 'Add a friend with their invite code', onTap: onAdd)
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
    final kit = Kit.of(context);
    return KitPanel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Activity', style: kit.heading),
        if (widget.items.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('When you or your friends hit a goal or finish a book, it shows up here.', style: kit.caption),
          ),
        for (final item in widget.items)
          Builder(builder: (context) {
            final id = item['id'] as String;
            final gave = item['gaveKudos'] == true || _given.contains(id);
            final count = (item['kudos'] as int) + (_given.contains(id) && item['gaveKudos'] != true ? 1 : 0);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                Text(switch (item['type']) { 'book_finished' => '📚', 'streak_milestone' => '🔥', _ => '✅' }, style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(item['text'] as String, style: kit.body),
                    Text(_ago(DateTime.parse(item['at'] as String)), style: kit.caption),
                  ]),
                ),
                if (item['mine'] == true)
                  if (count > 0) Text('👏 $count', style: kit.strong) else const SizedBox.shrink()
                else
                  KitChip(
                    label: count > 0 ? '👏 $count' : '👏 Kudos',
                    selected: gave,
                    onTap: gave
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
                  ),
              ]),
            );
          }),
      ]),
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
    final kit = Kit.of(context);
    final settings = ref.watch(settingsProvider);
    final habit = ref.watch(habitProvider);
    final notifier = ref.read(habitProvider.notifier);
    final monday = parseDateKey(weekKey(DateTime.now()));
    final week = [
      for (var d = 0; d < 7; d++) habit.stats[dateKey(DateTime(monday.year, monday.month, monday.day + d))] ?? const DailyStat(),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      KitPanel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Your week', style: kit.heading),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            for (var d = 0; d < 7; d++)
              Column(children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: week[d].meets(settings.goal) ? kit.accent : kit.field),
                ),
                const SizedBox(height: 4),
                Text('MTWTFSS'[d], style: kit.label.copyWith(letterSpacing: 0)),
              ]),
          ]),
          const SizedBox(height: 12),
          StreakBadge(days: notifier.displayStreak(), weekly: settings.goalMode == GoalMode.weekly),
        ]),
      ),
      const SizedBox(height: 14),
      KitPanel(
        padding: EdgeInsets.zero,
        child: const KitRow(
          icon: Icons.cloud_off_rounded,
          title: 'Friends and leagues need the Cloro server',
          subtitle: 'This build runs offline. Everything you read still counts toward your streak.',
        ),
      ),
    ]);
  }
}
