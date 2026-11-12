import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/habit/habit_engine.dart';
import '../../data/habit.dart';
import '../../data/notebook.dart';
import '../../data/settings_provider.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';
import '../share/share_sheet.dart';

/// Progress that shows growth, not just totals (UX_DESIGN.md §5.8).
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habit = ref.watch(habitProvider);
    final notebook = ref.watch(notebookProvider);
    final settings = ref.watch(settingsProvider);
    final streak = ref.read(habitProvider.notifier).displayStreak();
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
    final kit = Kit.of(context);
    return KitPage(
      title: settings.displayName,
      subtitle: 'Your reading, growing',
      actions: [
        KitIconButton(
          icon: Icons.reply_rounded,
          semanticLabel: 'Share progress',
          onPressed: () => showShareSheet(
            context,
            ProgressShare(
              emoji: '📖',
              headline: '${habit.totalVerifiedCards} cards read on BookReel',
              lines: ['$streak-day streak · best ${habit.streak.best}', '${habit.booksFinished} books finished'],
            ),
          ),
          child: const ShareArrowIcon(size: 22),
        ),
      ],
      children: [
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
                  final stat = stats[dateKey(day)];
                  final p = stat?.progress(goal) ?? 0;
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
