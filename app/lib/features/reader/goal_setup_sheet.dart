import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/habit/habit_engine.dart';
import '../../data/habit.dart';
import '../../data/settings.dart';
import '../../data/settings_provider.dart';
import '../../services/notifications.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';

/// Asked after the first few cards, when motivation is highest
/// (UX_DESIGN.md §5.9): daily goal + habit anchor ("After I ___, I'll read").
Future<void> showGoalSetup(BuildContext context) => showKitSheet<void>(
      context,
      title: 'Nice start! Set a small daily goal',
      subtitle: 'Small goals are easier to keep. You can change this anytime.',
      dismissible: false,
      builder: (_) => const _GoalSetup(),
    );

/// Today's goal: type, size, reminder and habit anchor. Opened from the
/// reader's flag pill, the Today ring and Settings.
Future<void> showGoalSheet(BuildContext context) => showKitSheet<void>(
      context,
      title: 'Daily goal',
      builder: (_) => const _GoalEditor(),
    );

/// The streak in detail: this week, best run, freezes. Opened from the
/// reader's flame pill and Today.
Future<void> showStreakSheet(BuildContext context) => showKitSheet<void>(
      context,
      title: 'Your streak',
      builder: (_) => const _StreakDetails(),
    );

Future<void> _reschedule(AppSettings s) => ReminderService.instance.scheduleDaily(
      enabled: s.reminderEnabled,
      hour: s.reminderHour,
      minute: s.reminderMinute,
      body: ReminderService.reminderBody(habitAnchor: s.habitAnchor, dailyGoal: s.dailyGoal),
    );

String _formatTime(BuildContext context, int hour, int minute) =>
    MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay(hour: hour, minute: minute),
        alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context));

class _GoalSetup extends ConsumerStatefulWidget {
  const _GoalSetup();

  @override
  ConsumerState<_GoalSetup> createState() => _GoalSetupState();
}

class _GoalSetupState extends ConsumerState<_GoalSetup> {
  int _goal = 20;
  String _anchor = '';
  TimeOfDay _time = const TimeOfDay(hour: 20, minute: 0);

  static const _anchors = ['After my morning tea', 'On my commute', 'After lunch', 'Before bed'];

  Future<void> _finish({required bool reminders}) async {
    ref.read(settingsProvider.notifier).update((s) => s.copyWith(
          dailyGoal: _goal,
          habitAnchor: _anchor,
          reminderEnabled: reminders,
          reminderHour: _time.hour,
          reminderMinute: _time.minute,
          goalSetupDone: true,
        ));
    if (reminders) {
      await ReminderService.instance.requestPermission();
      await _reschedule(ref.read(settingsProvider));
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    final quiet = ReminderService.isQuietHour(_time.hour);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      KitSegmented<int>(values: const [10, 20, 40], selected: _goal, label: (v) => '$v cards', onChanged: (v) => setState(() => _goal = v)),
      const SizedBox(height: 6),
      Text('≈ ${(_goal * 0.15).round()}–${(_goal * 0.3).round()} minutes a day', style: kit.caption),
      const SizedBox(height: 22),
      Text('When will you read?', style: kit.heading),
      const SizedBox(height: 2),
      Text('Linking reading to something you already do makes it stick.', style: kit.caption),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final a in _anchors) KitChip(label: a, selected: _anchor == a, onTap: () => setState(() => _anchor = _anchor == a ? '' : a)),
        KitChip(
          label: _anchors.contains(_anchor) || _anchor.isEmpty ? 'Something else…' : 'After I $_anchor',
          icon: Icons.edit_rounded,
          selected: _anchor.isNotEmpty && !_anchors.contains(_anchor),
          onTap: () async {
            final v = await showKitPrompt(context, title: 'After I…', hint: 'have my morning tea', initial: _anchors.contains(_anchor) ? '' : _anchor);
            if (v != null) setState(() => _anchor = v);
          },
        ),
      ]),
      const SizedBox(height: 18),
      KitPanel(
        padding: EdgeInsets.zero,
        child: KitRow(
          icon: Icons.notifications_rounded,
          title: 'One gentle reminder a day',
          subtitle: quiet ? 'That’s during quiet hours (10 pm–8 am). Pick another time.' : 'At ${_time.format(context)}',
          value: 'Change',
          onTap: () async {
            final t = await showKitTimePicker(context, initial: _time, title: 'Reminder time', subtitle: 'Never during quiet hours (10 pm–8 am)');
            if (t != null) setState(() => _time = t);
          },
        ),
      ),
      const SizedBox(height: 18),
      KitButton(label: 'Set goal & remind me', expand: true, onPressed: quiet ? null : () => _finish(reminders: true)),
      const SizedBox(height: 4),
      KitButton.ghost(label: 'No reminders', expand: true, onPressed: () => _finish(reminders: false)),
    ]);
  }
}

class _GoalEditor extends ConsumerWidget {
  const _GoalEditor();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kit = Kit.of(context);
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final today = ref.watch(habitProvider).today(DateTime.now());
    final goal = s.goal;
    final cards = s.goalUnit == GoalUnit.cards;
    final done = cards ? '${today.verifiedCards}' : '${today.minutes.floor()}';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Expanded(child: Text(today.meets(goal) ? 'Done for today ✓' : '$done of ${goal.dailyTarget} ${cards ? 'cards' : 'min'} today', style: kit.strong)),
        Text('${(today.progress(goal) * 100).round()}%', style: kit.strong),
      ]),
      const SizedBox(height: 8),
      KitProgress(value: today.progress(goal), height: 8),
      const SizedBox(height: 20),
      KitSegmented<GoalMode>(
        values: GoalMode.values,
        selected: s.goalMode,
        label: (m) => m == GoalMode.daily ? 'Daily streak' : 'Days per week',
        onChanged: (m) => n.update((x) => x.copyWith(goalMode: m)),
      ),
      const SizedBox(height: 16),
      Text('Each day', style: kit.label),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final g in const [10, 20, 40, 60])
          KitChip(label: '$g ${cards ? 'cards' : 'min'}', selected: s.dailyGoal == g, onTap: () => n.update((x) => x.copyWith(dailyGoal: g))),
        KitChip(
          label: cards ? 'Count minutes' : 'Count cards',
          icon: Icons.swap_horiz_rounded,
          onTap: () => n.update((x) => x.copyWith(goalUnit: cards ? GoalUnit.minutes : GoalUnit.cards)),
        ),
      ]),
      if (s.goalMode == GoalMode.weekly) ...[
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: Text('Days a week', style: kit.label)),
          Text('${s.weeklyDays}', style: kit.strong),
        ]),
        KitSlider(
          value: s.weeklyDays.toDouble(),
          min: 2,
          max: 7,
          divisions: 5,
          semanticLabel: 'Days a week',
          format: (v) => '${v.round()} days',
          onChanged: (v) => n.update((x) => x.copyWith(weeklyDays: v.round())),
        ),
      ],
      const SizedBox(height: 18),
      KitGroup(divided: true, children: [
        MergeSemantics(
          child: KitRow(
            icon: Icons.notifications_rounded,
            title: 'Daily reminder',
            subtitle: s.reminderEnabled ? 'Never during quiet hours (10 pm–8 am)' : 'Off',
            chevron: false,
            trailing: KitSwitch(
              value: s.reminderEnabled,
              onChanged: (v) async {
                n.update((x) => x.copyWith(reminderEnabled: v));
                if (v) await ReminderService.instance.requestPermission();
                await _reschedule(ref.read(settingsProvider));
              },
            ),
          ),
        ),
        if (s.reminderEnabled)
          KitRow(
            icon: Icons.schedule_rounded,
            title: 'Reminder time',
            value: _formatTime(context, s.reminderHour, s.reminderMinute),
            onTap: () async {
              final t = await showKitTimePicker(context,
                  initial: TimeOfDay(hour: s.reminderHour, minute: s.reminderMinute),
                  title: 'Reminder time',
                  subtitle: 'Never during quiet hours (10 pm–8 am)');
              if (t == null || !context.mounted) return;
              if (ReminderService.isQuietHour(t.hour)) {
                showKitToast(context, 'That’s during quiet hours (10 pm–8 am). Pick another time.', emoji: '🌙');
                return;
              }
              n.update((x) => x.copyWith(reminderHour: t.hour, reminderMinute: t.minute));
              await _reschedule(ref.read(settingsProvider));
            },
          ),
        KitRow(
          icon: Icons.link_rounded,
          title: 'Habit anchor',
          value: s.habitAnchor.isEmpty ? 'Not set' : s.habitAnchor,
          onTap: () async {
            final v = await showKitPrompt(context, title: 'After I…', hint: 'have my morning tea', initial: s.habitAnchor);
            if (v == null) return;
            n.update((x) => x.copyWith(habitAnchor: v));
            await _reschedule(ref.read(settingsProvider));
          },
        ),
      ]),
    ]);
  }
}

class _StreakDetails extends ConsumerWidget {
  const _StreakDetails();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kit = Kit.of(context);
    final habit = ref.watch(habitProvider);
    final notifier = ref.read(habitProvider.notifier);
    final s = ref.watch(settingsProvider);
    final goal = s.goal;
    final weekly = goal.mode == GoalMode.weekly;
    final streak = notifier.displayStreak();
    final freezes = notifier.freezesLeft();
    final now = DateTime.now();
    // Monday-first week, like the leagues.
    final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
    const names = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Icon(Icons.local_fire_department_rounded, size: 46, color: streak > 0 ? ember : kit.inkSoft),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$streak ${weekly ? (streak == 1 ? 'week' : 'weeks') : (streak == 1 ? 'day' : 'days')}', style: kit.display),
            Text(weekly ? '${notifier.activeDaysThisWeek()} of ${goal.weeklyDays} days done this week' : 'Best: ${habit.streak.best} days',
                style: kit.caption),
          ]),
        ),
      ]),
      const SizedBox(height: 18),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        for (var d = 0; d < 7; d++)
          Builder(builder: (context) {
            final day = DateTime(monday.year, monday.month, monday.day + d);
            final stat = habit.stats[dateKey(day)];
            final met = stat != null && stat.meets(goal);
            final isToday = d == now.weekday - 1;
            final future = day.isAfter(now);
            return Semantics(
              label: '${names[d]}: ${met ? 'goal met' : future ? 'to come' : 'not yet'}',
              child: Column(children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: met ? kit.ink : kit.field,
                    border: Border.all(color: isToday ? kit.ink : kit.stroke, width: isToday ? 2 : 1),
                  ),
                  alignment: Alignment.center,
                  child: met
                      ? Icon(Icons.check_rounded, size: 20, color: kit.inverse)
                      : Text('${day.day}', style: kit.caption.copyWith(color: future ? kit.inkSoft.withValues(alpha: 0.5) : kit.ink)),
                ),
                const SizedBox(height: 4),
                Text(names[d], style: kit.label.copyWith(letterSpacing: 0)),
              ]),
            );
          }),
      ]),
      const SizedBox(height: 18),
      KitGroup(divided: true, children: [
        KitRow(
          icon: Icons.ac_unit_rounded,
          title: '$freezes streak freeze${freezes == 1 ? '' : 's'} left',
          subtitle: 'A freeze covers a missed day. Your plan gives ${s.tier.freezes} a week.',
        ),
        KitRow(
          icon: Icons.flag_rounded,
          title: 'Daily goal',
          value: '${goal.dailyTarget} ${goal.unit == GoalUnit.cards ? 'cards' : 'min'}',
          onTap: () {
            // Open the goal sheet from the navigator, not from this closing sheet.
            final navigator = Navigator.of(context);
            navigator.pop();
            showGoalSheet(navigator.context);
          },
        ),
      ]),
    ]);
  }
}
