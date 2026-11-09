import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/habit/habit_engine.dart';
import '../../data/habit.dart';
import '../../data/settings_provider.dart';
import '../../ui/widgets.dart';

/// Friends tab. Leagues, the activity feed and kudos need accounts and the
/// backend (IMPLEMENTATION_PLAN.md Phase 7); until then this shows the
/// reader's own week and an invite.
class FriendsScreen extends ConsumerWidget {
  const FriendsScreen({super.key});

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
    final minutes = week.fold(0.0, (s, d) => s + d.minutes);
    final cards = week.fold(0, (s, d) => s + d.verifiedCards);

    return Scaffold(
      appBar: AppBar(title: const Text('Friends')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Your week', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _Stat(value: '${minutes.round()}', label: 'minutes'),
                _Stat(value: '$cards', label: 'cards'),
                _Stat(value: '${notifier.activeDaysThisWeek()}/7', label: 'goal days'),
              ]),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                for (var d = 0; d < 7; d++)
                  Column(children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: week[d].meets(settings.goal) ? const Color(0xFFE08A2E) : theme.colorScheme.surfaceContainerHighest,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('MTWTFSS'[d], style: theme.textTheme.bodySmall),
                  ]),
              ]),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.emoji_events_outlined),
                const SizedBox(width: 8),
                Text('Leagues & friends', style: theme.textTheme.titleMedium),
              ]),
              const SizedBox(height: 8),
              const Text(
                'Weekly leagues with ~24 readers at your level, friend activity and kudos arrive with accounts. '
                'Leagues rank consistency (days and verified minutes), never speed.',
              ),
              const SizedBox(height: 12),
              StreakBadge(days: notifier.displayStreak(), weekly: settings.goalMode == GoalMode.weekly),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: () => SharePlus.instance.share(ShareParams(
            text: 'I’m building a reading habit on BookReel: books as bite-sized cards. '
                'Join me and let’s keep each other going! https://bookreel.app/invite',
          )),
          icon: const Icon(Icons.person_add_alt),
          label: const Text('Invite a friend'),
        ),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ]);
}
