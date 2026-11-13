import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/habit/habit_engine.dart';
import '../../data/habit.dart';
import '../../data/library.dart';
import '../../data/notebook.dart';
import '../../data/settings_provider.dart';
import '../../ui/kit.dart';
import '../../ui/vibes.dart';
import '../../ui/widgets.dart';
import '../profile/profile_screen.dart';
import '../reader/goal_setup_sheet.dart';

/// Today (home): one main action, today's goal ring and streak, one social
/// line (UX_DESIGN.md §5.1), on the reader's moving scene.
class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key});

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(libraryProvider.notifier).ensureStarterBook());
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    final settings = ref.watch(settingsProvider);
    final habit = ref.watch(habitProvider);
    ref.watch(libraryProvider);
    final library = ref.read(libraryProvider.notifier);
    final current = library.current;
    final notifier = ref.read(habitProvider.notifier);
    final today = habit.today(DateTime.now());
    final goal = settings.goal;
    final weekly = goal.mode == GoalMode.weekly;
    final streak = notifier.displayStreak();
    final dueWords = ref.watch(notebookProvider).dueWords(DateTime.now()).length;
    final value = goal.unit == GoalUnit.cards ? '${today.verifiedCards}' : today.minutes.floor().toString();
    final style = vibeStyles[settings.vibe]!;
    final freezes = notifier.freezesLeft();

    return KitPage(
      back: false,
      backdrop: false,
      dock: true,
      title: '${_greeting()}${settings.displayName == 'Reader' ? '' : ','}',
      subtitle: settings.displayName == 'Reader' ? '${style.emoji} ${style.tagline}' : settings.displayName,
      actions: [
        KitIconButton(
          icon: Icons.person_outline_rounded,
          semanticLabel: 'Your profile',
          onPressed: () => context.push('/profile'),
          child: ReaderAvatar(settings: settings, size: 40, ring: today.meets(goal)),
        ),
        KitIconButton(icon: Icons.settings_rounded, semanticLabel: 'Settings', onPressed: () => context.push('/settings')),
      ],
      children: [
        // Today's goal and streak, straight on the scene.
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            KitPressable(
              onTap: () => showGoalSheet(context),
              semanticLabel: 'Daily goal: $value of ${goal.dailyTarget}. Change goal',
              excludeSemantics: true,
              child: GoalRing(
                progress: today.progress(goal),
                label: '$value / ${goal.dailyTarget}',
                sublabel: goal.unit == GoalUnit.cards ? 'cards today' : 'min today',
                size: 132,
              ),
            ),
            Flexible(
              child: KitPressable(
                onTap: () => showStreakSheet(context),
                semanticLabel: '$streak ${weekly ? 'week' : 'day'} streak. Details',
                excludeSemantics: true,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  StreakBadge(days: streak, weekly: weekly),
                  const SizedBox(height: 6),
                  Text(
                    weekly
                        ? '${notifier.activeDaysThisWeek()} of ${goal.weeklyDays} days this week'
                        : '$freezes streak freeze${freezes == 1 ? '' : 's'} left',
                    style: kit.caption,
                  ),
                  const SizedBox(height: 8),
                  Text(today.meets(goal) ? 'Goal done ✓' : 'Tap to see your week',
                      style: kit.strong.copyWith(fontSize: 14, color: today.meets(goal) ? kit.accent : kit.ink)),
                ]),
              ),
            ),
          ]),
        ),
        if (current != null)
          KitPanel(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              BookCover(book: current, width: 76),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(current.title, style: kit.heading, maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text('${(current.progress * 100).round()}% · ~${_minutesLeft(current.wordCount, current.progress, habit.wpm)} min left',
                      style: kit.caption),
                  const SizedBox(height: 10),
                  KitProgress(value: current.progress),
                  const SizedBox(height: 16),
                  KitButton(
                    label: 'Continue reading',
                    icon: Icons.play_arrow_rounded,
                    expand: true,
                    onPressed: () => context.push('/read/${current.id}'),
                  ),
                ]),
              ),
            ]),
          )
        else
          KitPanel(
            padding: EdgeInsets.zero,
            child: KitRow(
              icon: Icons.auto_stories_rounded,
              title: 'Pick a book to start',
              subtitle: 'Import an EPUB or PDF, or try a classic.',
              onTap: () => context.go('/library'),
            ),
          ),
        if (dueWords > 0) ...[
          const SizedBox(height: 12),
          KitPanel(
            padding: EdgeInsets.zero,
            child: KitRow(
              icon: Icons.style_rounded,
              title: '$dueWords word${dueWords == 1 ? '' : 's'} to review',
              subtitle: 'A quick review helps new words stick',
              onTap: () => context.push('/review'),
            ),
          ),
        ],
        if (!settings.hideLeaderboards) ...[
          const SizedBox(height: 12),
          KitPanel(
            padding: EdgeInsets.zero,
            child: KitRow(
              icon: Icons.people_rounded,
              title: 'Read with friends',
              subtitle: 'Invite a friend and keep each other going',
              onTap: () => context.go('/friends'),
            ),
          ),
        ],
      ],
    );
  }

  int _minutesLeft(int words, double progress, double wpm) => ((words * (1 - progress)) / wpm).ceil();
}
