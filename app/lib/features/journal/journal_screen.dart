import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/habit/habit_engine.dart';
import '../../data/api_client.dart';
import '../../data/habit.dart';
import '../../data/library.dart';
import '../../data/notebook.dart';
import '../../data/settings_provider.dart';
import '../../ui/kit.dart';
import '../../ui/widgets.dart';
import '../profile/profile_screen.dart';
import '../reader/goal_setup_sheet.dart';
import 'feed.dart';
import '../../l10n/l10n.dart';

/// Journal (Cloro plan §10; the tab was called Today), Strava-style: today's
/// goal ring and streak, the book to continue (its progress drawn round its
/// cover), then the feed of your reading sessions and milestones and those
/// of readers you follow, with kudos and comments. Blue is how much you've
/// read, green is a goal met (UX_DESIGN.md §6.6).
class JournalScreen extends ConsumerStatefulWidget {
  const JournalScreen({super.key});

  @override
  ConsumerState<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends ConsumerState<JournalScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(libraryProvider.notifier).ensureStarterBook());
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return tr('Good morning');
    if (h < 17) return tr('Good afternoon');
    return tr('Good evening');
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
    final freezes = notifier.freezesLeft();

    final api = ref.watch(apiProvider);
    final feed = ref.watch(journalFeedProvider);
    return KitPage(
      back: false,
      backdrop: false,
      dock: true,
      onRefresh: () => ref.refresh(journalFeedProvider.future),
      leading: const CloroLogo(size: 40),
      title: tr('Journal'),
      subtitle: settings.displayName == 'Reader'
          ? tr('{greeting} · a few calm minutes with a book', {'greeting': _greeting()})
          : tr('{greeting}, {name}', {'greeting': _greeting(), 'name': settings.displayName}),
      actions: [
        KitIconButton(
          icon: Icons.person_outline_rounded,
          semanticLabel: tr('Your profile'),
          onPressed: () => context.go('/profile'),
          child: ReaderAvatar(settings: settings, size: 40, ring: today.meets(goal)),
        ),
        KitIconButton(icon: Icons.settings_rounded, semanticLabel: tr('Settings'), onPressed: () => context.push('/settings')),
      ],
      children: [
        // Today's goal and streak, straight on the scene.
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            KitPressable(
              onTap: () => showGoalSheet(context),
              semanticLabel: tr('Daily goal: {done} of {goal}. Change goal', {'done': value, 'goal': goal.dailyTarget}),
              excludeSemantics: true,
              child: GoalRing(
                progress: today.progress(goal),
                label: '$value / ${goal.dailyTarget}',
                sublabel: goal.unit == GoalUnit.cards ? tr('cards today') : tr('min today'),
                size: 132,
              ),
            ),
            Flexible(
              child: KitPressable(
                onTap: () => showStreakSheet(context),
                semanticLabel: weekly ? tr('{n} week streak. Details', {'n': streak}) : tr('{n} day streak. Details', {'n': streak}),
                excludeSemantics: true,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  StreakBadge(days: streak, weekly: weekly),
                  const SizedBox(height: 6),
                  Text(
                    weekly
                        ? tr('{done} of {days} days this week', {'done': notifier.activeDaysThisWeek(), 'days': goal.weeklyDays})
                        : trn(freezes, '{n} streak freeze left', '{n} streak freezes left'),
                    style: kit.caption,
                  ),
                  const SizedBox(height: 8),
                  Text(today.meets(goal) ? tr('Goal done ✓') : tr('Tap to see your week'),
                      style: kit.strong.copyWith(fontSize: 14, color: today.meets(goal) ? kit.growth : kit.ink)),
                ]),
              ),
            ),
          ]),
        ),
        if (current != null)
          KitPanel(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // How far you are, drawn round the cover.
              ProgressCover(book: current, width: 76),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(current.title, style: kit.heading, maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(
                        text: '${(current.progress * 100).round()}%',
                        style: TextStyle(color: kit.activity, fontWeight: FontWeight.w800),
                      ),
                      TextSpan(text: tr(' read · ~{n} min left', {'n': _minutesLeft(current.wordCount, current.progress, habit.wpm)})),
                    ]),
                    style: kit.caption,
                  ),
                  const SizedBox(height: 18),
                  KitButton(
                    label: tr('Continue reading'),
                    icon: Icons.play_arrow_rounded,
                    expand: true,
                    onPressed: () => context.go('/read/${current.id}'),
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
              title: tr('Pick a book to start'),
              subtitle: tr('Import an EPUB or PDF, or try a classic.'),
              onTap: () => context.go('/library'),
            ),
          ),
        if (dueWords > 0) ...[
          const SizedBox(height: 12),
          KitPanel(
            padding: EdgeInsets.zero,
            child: KitRow(
              icon: Icons.style_rounded,
              title: trn(dueWords, '{n} word to review', '{n} words to review'),
              subtitle: tr('A quick review helps new words stick'),
              onTap: () => context.push('/review'),
            ),
          ),
        ],
        if (!settings.hideLeaderboards && api.enabled) ...[
          const SizedBox(height: 12),
          KitPanel(
            padding: EdgeInsets.zero,
            child: KitRow(
              icon: Icons.emoji_events_outlined,
              title: tr('This week’s league'),
              subtitle: tr('Read alongside readers like you'),
              onTap: () => context.push('/friends'),
            ),
          ),
        ],
        const KitDivider(),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Row(children: [
            Expanded(child: Text(tr('Activity'), style: kit.heading)),
            if (api.enabled)
              KitIconButton(
                icon: Icons.person_search_rounded,
                semanticLabel: tr('Find people'),
                onPressed: () => context.push('/people/me?tab=following'),
              ),
          ]),
        ),
        ...feed.when(
          loading: () => const [Padding(padding: EdgeInsets.all(40), child: Center(child: KitSpinner()))],
          error: (e, _) => [
            KitEmpty(
              emoji: '☁️',
              title: tr('Can’t reach Cloro right now'),
              message: tr('Your reading is saved and will sync later.'),
              action: KitButton.secondary(label: tr('Try again'), onPressed: () => ref.invalidate(journalFeedProvider)),
            ),
          ],
          data: (page) => page.items.isEmpty
              ? [
                  KitEmpty(
                    emoji: '📖',
                    title: api.enabled ? tr('Your feed is quiet') : tr('Your reading shows here'),
                    message: api.enabled
                        ? tr('Read a few cards, or follow readers to see their reading, kudos and comments here.')
                        : tr('Each reading session appears here: the book, minutes and cards.'),
                    action: api.enabled
                        ? KitButton.secondary(label: tr('Find people'), onPressed: () => context.push('/people/me?tab=following'))
                        : null,
                  ),
                ]
              : [
                  if (page.offline)
                    KitRow(
                      icon: Icons.cloud_off_rounded,
                      title: tr('Can’t reach Cloro right now'),
                      subtitle: tr('Your reading is saved and will sync later.'),
                      trailing: KitIconButton(icon: Icons.refresh_rounded, semanticLabel: tr('Try again'), glass: false, onPressed: () => ref.invalidate(journalFeedProvider)),
                    ),
                  for (final (i, e) in page.items.indexed) ...[
                    if (i > 0) const KitDivider(),
                    ActivityCard(key: ValueKey(e.id), entry: e),
                  ],
                  if (page.more) FeedLoadMore(key: ValueKey(page.items.length)),
                ],
        ),
      ],
    );
  }

  int _minutesLeft(int words, double progress, double wpm) => ((words * (1 - progress)) / wpm).ceil();
}
