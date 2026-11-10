import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/habit/habit_engine.dart';
import '../../data/habit.dart';
import '../../data/library.dart';
import '../../data/notebook.dart';
import '../../data/settings_provider.dart';
import '../../data/settings.dart';
import '../../ui/theme.dart';
import '../../ui/vibes.dart';
import '../../ui/widgets.dart';

/// Today (home): one main action, today's goal ring and streak, one social
/// line (UX_DESIGN.md §5.1).
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
    final theme = Theme.of(context);
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
    final onScene = settings.vibe != Vibe.paper;
    final heroTheme = onScene ? buildAppTheme(brightness: Brightness.dark) : theme;
    final top = MediaQuery.paddingOf(context).top;

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Hero: today's goal and streak over the reader's chosen scene.
          SizedBox(
            height: top + 300,
            child: Stack(fit: StackFit.expand, children: [
              VibeBackground(vibe: settings.vibe, animate: settings.animatedBackground, paperColor: theme.colorScheme.surface),
              if (onScene)
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x66000000), Color(0x40000000), Color(0x73000000)],
                    ),
                  ),
                ),
              Theme(
                data: heroTheme,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, top + 8, 8, 16),
                  child: Column(children: [
                    Row(children: [
                      Expanded(
                        child: Text(
                          '${_greeting()}${settings.displayName == 'Reader' ? '' : ', ${settings.displayName}'}',
                          style: heroTheme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            shadows: onScene ? const [Shadow(color: Color(0x66000000), blurRadius: 10)] : null,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Your progress',
                        onPressed: () => context.push('/profile'),
                        icon: const CircleAvatar(child: Icon(Icons.person_outline)),
                      ),
                      IconButton(tooltip: 'Settings', onPressed: () => context.push('/settings'), icon: const Icon(Icons.settings_outlined)),
                    ]),
                    const Spacer(),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                      GoalRing(
                        progress: today.progress(goal),
                        label: '$value / ${goal.dailyTarget}',
                        sublabel: goal.unit == GoalUnit.cards ? 'cards today' : 'min today',
                      ),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        StreakBadge(days: streak, weekly: weekly),
                        const SizedBox(height: 6),
                        if (weekly)
                          Text('${notifier.activeDaysThisWeek()} of ${goal.weeklyDays} days this week', style: heroTheme.textTheme.bodySmall)
                        else
                          Text('${notifier.freezesLeft()} streak freeze${notifier.freezesLeft() == 1 ? '' : 's'} left',
                              style: heroTheme.textTheme.bodySmall),
                        const SizedBox(height: 6),
                        Text(today.meets(goal) ? 'Goal done ✓' : '${style.emoji} ${style.tagline}',
                            style: heroTheme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                      ]),
                    ]),
                    const Spacer(),
                  ]),
                ),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (current != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    BookCover(book: current, width: 72),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(current.title, style: theme.textTheme.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Text('${(current.progress * 100).round()}% · ~${_minutesLeft(current.wordCount, current.progress, habit.wpm)} min left',
                            style: theme.textTheme.bodySmall),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(value: current.progress, borderRadius: BorderRadius.circular(4)),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                            onPressed: () => context.push('/read/${current.id}'),
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: const Text('Continue reading'),
                          ),
                        ),
                      ]),
                    ),
                  ]),
                ),
              )
            else
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: const Icon(Icons.auto_stories_outlined, size: 32),
                  title: const Text('Pick a book to start'),
                  subtitle: const Text('Import an EPUB or PDF, or try a classic.'),
                  onTap: () => context.go('/library'),
                ),
              ),
            if (dueWords > 0) ...[
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.style_outlined),
                  title: Text('$dueWords word${dueWords == 1 ? '' : 's'} to review'),
                  subtitle: const Text('A quick review helps new words stick'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/review'),
                ),
              ),
            ],
            if (!settings.hideLeaderboards) ...[
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.people_outline),
                  title: const Text('Read with friends'),
                  subtitle: const Text('Invite a friend and keep each other going'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go('/friends'),
                ),
              ),
            ],
          ]),
        ),
      ]),
    );
  }

  int _minutesLeft(int words, double progress, double wpm) => ((words * (1 - progress)) / wpm).ceil();
}
