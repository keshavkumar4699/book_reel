import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/settings_provider.dart';
import '../../services/notifications.dart';

/// Asked after the first few cards, when motivation is highest
/// (UX_DESIGN.md §5.9): daily goal + habit anchor ("After I ___, I'll read").
Future<void> showGoalSetup(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      builder: (_) => const _GoalSetup(),
    );

class _GoalSetup extends ConsumerStatefulWidget {
  const _GoalSetup();

  @override
  ConsumerState<_GoalSetup> createState() => _GoalSetupState();
}

class _GoalSetupState extends ConsumerState<_GoalSetup> {
  int _goal = 20;
  final _anchor = TextEditingController();
  TimeOfDay _time = const TimeOfDay(hour: 20, minute: 0);

  static const _anchors = ['After my morning tea', 'On my commute', 'After lunch', 'Before bed'];

  @override
  void dispose() {
    _anchor.dispose();
    super.dispose();
  }

  Future<void> _finish({required bool reminders}) async {
    final anchor = _anchor.text.trim();
    ref.read(settingsProvider.notifier).update((s) => s.copyWith(
          dailyGoal: _goal,
          habitAnchor: anchor,
          reminderEnabled: reminders,
          reminderHour: _time.hour,
          reminderMinute: _time.minute,
          goalSetupDone: true,
        ));
    if (reminders) {
      await ReminderService.instance.requestPermission();
      await ReminderService.instance.scheduleDaily(
        enabled: true,
        hour: _time.hour,
        minute: _time.minute,
        body: ReminderService.reminderBody(habitAnchor: anchor, dailyGoal: _goal),
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quiet = ReminderService.isQuietHour(_time.hour);
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('Nice start! Set a small daily goal', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('Small goals are easier to keep. You can change this anytime.', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 16),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 10, label: Text('10 cards')),
              ButtonSegment(value: 20, label: Text('20 cards')),
              ButtonSegment(value: 40, label: Text('40 cards')),
            ],
            selected: {_goal},
            onSelectionChanged: (v) => setState(() => _goal = v.first),
          ),
          const SizedBox(height: 4),
          Text('≈ ${(_goal * 0.15).round()}–${(_goal * 0.3).round()} minutes a day', style: theme.textTheme.bodySmall),
          const SizedBox(height: 24),
          Text('When will you read?', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('Linking reading to something you already do makes it stick.', style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final a in _anchors)
              ActionChip(label: Text(a), onPressed: () => setState(() => _anchor.text = a)),
          ]),
          const SizedBox(height: 8),
          TextField(
            controller: _anchor,
            decoration: const InputDecoration(
              prefixText: 'After I… ',
              hintText: 'have my morning tea',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('One gentle reminder a day'),
            subtitle: Text(quiet ? 'That’s during quiet hours (10 pm–8 am). Pick another time.' : 'At ${_time.format(context)}'),
            trailing: TextButton(
              onPressed: () async {
                final t = await showTimePicker(context: context, initialTime: _time);
                if (t != null) setState(() => _time = t);
              },
              child: const Text('Change'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: quiet ? null : () => _finish(reminders: true),
              child: const Text('Set goal & remind me'),
            ),
          ),
          Center(child: TextButton(onPressed: () => _finish(reminders: false), child: const Text('No reminders'))),
        ]),
      ),
    );
  }
}
