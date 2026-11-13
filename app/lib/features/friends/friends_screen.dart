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
import '../../ui/widgets.dart';

class FriendsData {
  const FriendsData({required this.me, required this.league, required this.board});
  final Map<String, dynamic> me;
  final Map<String, dynamic>? league;
  final List<Map<String, dynamic>> board;
}

final friendsDataProvider = FutureProvider.autoDispose<FriendsData>((ref) async {
  final api = ref.read(apiProvider);
  // Upload pending reading first so the tables include today.
  await ref.read(syncServiceProvider).syncNow();
  final results = await Future.wait([api.me(), api.league(), api.friendsBoard()]);
  return FriendsData(
    me: results[0]! as Map<String, dynamic>,
    league: results[1] as Map<String, dynamic>?,
    board: results[2]! as List<Map<String, dynamic>>,
  );
});

/// League (opened from Today): this week's league of similar readers and the
/// board of readers you follow, plus your invite. The activity feed with
/// kudos and comments is on Today (Cloro plan §10).
class FriendsScreen extends ConsumerWidget {
  const FriendsScreen({super.key, this.asPage = false});

  /// Opened from Profile or Today (a page with a back button), not a tab.
  final bool asPage;

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
                InviteCard(code: d.me['invite_code'] as String, url: d.me['invite_url'] as String),
                if (!settings.hideLeaderboards && d.league != null) ...[
                  const SizedBox(height: 14),
                  _LeagueCard(league: d.league!),
                ],
                if (!settings.hideLeaderboards) ...[
                  const SizedBox(height: 14),
                  _FriendsBoard(rows: d.board, onAdd: () => _addFriend(context, ref)),
                ],
              ],
            );
    return KitPage(
      back: asPage,
      backdrop: asPage,
      dock: !asPage,
      title: 'League',
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
      title: 'Follow by invite code',
      message: 'Enter their invite code: you’ll follow each other',
      hint: 'e.g. 7PA756JQ',
      confirm: 'Add',
      capitalization: TextCapitalization.characters,
    );
    if (code == null || code.isEmpty || !context.mounted) return;
    try {
      final name = await ref.read(apiProvider).addFriend(code);
      if (!context.mounted) return;
      showKitToast(context, name == null ? 'No reader found with that code.' : 'You and $name now follow each other 🎉');
      if (name != null) ref.invalidate(friendsDataProvider);
    } catch (_) {
      if (context.mounted) showKitToast(context, 'Couldn’t add friend. Check your connection.', icon: Icons.cloud_off_rounded);
    }
  }
}

/// Your invite code and link: a personal invitation (you then follow each other).
class InviteCard extends StatelessWidget {
  const InviteCard({super.key, required this.code, required this.url});
  final String code;
  final String url;

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    return KitPanel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Read with friends', style: kit.heading),
        const SizedBox(height: 2),
        Text('Share your code: whoever uses it, you follow each other.', style: kit.caption),
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
          Icon(Icons.emoji_events_rounded, color: kit.ink),
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
      child: Row(children: [
        SizedBox(width: 28, child: Text('$rank', style: kit.strong)),
        Expanded(child: Text(me ? '$name (you)' : name, overflow: TextOverflow.ellipsis, style: kit.body)),
        Text(detail, style: kit.caption),
        const SizedBox(width: 6),
        // Neutral colours: moving down is shown, never shamed (UX_DESIGN.md §6.2).
        Icon(
          switch (zone) { _Zone.up => Icons.arrow_upward_rounded, _Zone.down => Icons.arrow_downward_rounded, _Zone.none => Icons.remove_rounded },
          size: 16,
          color: zone == _Zone.up ? kit.ink : kit.inkSoft.withValues(alpha: zone == _Zone.none ? 0.3 : 1),
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
                  decoration: BoxDecoration(shape: BoxShape.circle, color: week[d].meets(settings.goal) ? kit.ink : kit.field),
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
