import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/habit/habit_engine.dart';
import '../../core/segmentation/rule_segmenter.dart';
import '../../core/text/lexicon.dart';
import '../../data/ai_client.dart';
import '../../data/settings.dart';
import '../../data/settings_provider.dart';
import '../../services/notifications.dart';
import '../../ui/theme.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final theme = Theme.of(context);
    Widget header(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Text(t, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
        );

    Future<void> reschedule(AppSettings next) => ReminderService.instance.scheduleDaily(
          enabled: next.reminderEnabled,
          hour: next.reminderHour,
          minute: next.reminderMinute,
          body: ReminderService.reminderBody(habitAnchor: next.habitAnchor, dailyGoal: next.dailyGoal),
        );

    final preview = ReadingTheme.of(effectiveReadingTheme(s, MediaQuery.platformBrightnessOf(context)));

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(children: [
        // Live preview of the reading surface.
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: preview.background, borderRadius: BorderRadius.circular(16)),
          child: Text(
            'The best time to plant a tree was twenty years ago. The second best time is now.',
            style: TextStyle(
              fontFamily: fontFamilyFor(s.font),
              fontSize: s.fontSize,
              height: s.lineHeight,
              letterSpacing: s.letterSpacing,
              wordSpacing: s.wordSpacing,
              color: preview.text,
            ),
          ),
        ),
        header('Reading'),
        ListTile(
          title: const Text('Theme'),
          subtitle: Wrap(spacing: 8, children: [
            for (final t in ReadingThemeId.values)
              ChoiceChip(
                label: Text(t.name[0].toUpperCase() + t.name.substring(1)),
                selected: s.theme == t,
                onSelected: (_) => n.update((x) => x.copyWith(theme: t)),
              ),
          ]),
        ),
        SwitchListTile(
          title: const Text('Use dark theme when the phone is in dark mode'),
          value: s.followSystemDark,
          onChanged: (v) => n.update((x) => x.copyWith(followSystemDark: v)),
        ),
        ListTile(
          title: const Text('Font'),
          subtitle: Wrap(spacing: 8, children: [
            for (final f in ReadingFont.values)
              ChoiceChip(
                label: Text(switch (f) {
                  ReadingFont.literata => 'Literata',
                  ReadingFont.atkinson => 'Atkinson Hyperlegible',
                  ReadingFont.system => 'System',
                }),
                selected: s.font == f,
                onSelected: (_) => n.update((x) => x.copyWith(font: f)),
              ),
          ]),
        ),
        _SliderTile(
          label: 'Text size',
          value: s.fontSize,
          min: 14,
          max: 32,
          divisions: 18,
          display: '${s.fontSize.round()}',
          onChanged: (v) => n.update((x) => x.copyWith(fontSize: v)),
        ),
        _SliderTile(
          label: 'Line spacing',
          value: s.lineHeight,
          min: 1.2,
          max: 2.0,
          divisions: 8,
          display: s.lineHeight.toStringAsFixed(1),
          onChanged: (v) => n.update((x) => x.copyWith(lineHeight: v)),
        ),
        _SliderTile(
          label: 'Letter spacing',
          help: 'Wider spacing can make reading easier, especially with dyslexia.',
          value: s.letterSpacing,
          min: 0,
          max: 2,
          divisions: 8,
          display: s.letterSpacing.toStringAsFixed(2),
          onChanged: (v) => n.update((x) => x.copyWith(letterSpacing: v, wordSpacing: v * 2)),
        ),
        ListTile(
          title: const Text('Card length'),
          subtitle: SegmentedButton<CardLength>(
            segments: const [
              ButtonSegment(value: CardLength.bite, label: Text('Bite')),
              ButtonSegment(value: CardLength.standard, label: Text('Standard')),
              ButtonSegment(value: CardLength.deep, label: Text('Deep')),
            ],
            selected: {s.cardLength},
            onSelectionChanged: (v) => n.update((x) => x.copyWith(cardLength: v.first)),
          ),
        ),
        ListTile(
          title: const Text('Key points'),
          subtitle: SegmentedButton<KeyPointStyle>(
            segments: const [
              ButtonSegment(value: KeyPointStyle.off, label: Text('Off')),
              ButtonSegment(value: KeyPointStyle.subtle, label: Text('Subtle')),
              ButtonSegment(value: KeyPointStyle.bold, label: Text('Bold')),
            ],
            selected: {s.keyPointStyle},
            onSelectionChanged: (v) => n.update((x) => x.copyWith(keyPointStyle: v.first)),
          ),
        ),
        SwitchListTile(
          title: const Text('Underline hard words'),
          value: s.underlineHardWords,
          onChanged: (v) => n.update((x) => x.copyWith(underlineHardWords: v)),
        ),
        ListTile(
          title: const Text('Vocabulary level'),
          subtitle: SegmentedButton<ReadingLevel>(
            segments: const [
              ButtonSegment(value: ReadingLevel.beginner, label: Text('Beginner')),
              ButtonSegment(value: ReadingLevel.intermediate, label: Text('Middle')),
              ButtonSegment(value: ReadingLevel.advanced, label: Text('Advanced')),
            ],
            selected: {s.readingLevel},
            onSelectionChanged: (v) => n.update((x) => x.copyWith(readingLevel: v.first)),
          ),
        ),
        SwitchListTile(
          title: const Text('AI card titles'),
          subtitle: const Text('Shown when AI cards are available'),
          value: s.showAiTitles,
          onChanged: (v) => n.update((x) => x.copyWith(showAiTitles: v)),
        ),
        SwitchListTile(
          title: const Text('Quick-check cards'),
          subtitle: const Text('A one-tap recall check every ~10 cards'),
          value: s.recallCards,
          onChanged: (v) => n.update((x) => x.copyWith(recallCards: v)),
        ),
        SwitchListTile(
          title: const Text('Reflect cards'),
          subtitle: const Text('One question at the end of each chapter'),
          value: s.reflectCards,
          onChanged: (v) => n.update((x) => x.copyWith(reflectCards: v)),
        ),
        header('Goal & reminders'),
        ListTile(
          title: const Text('Goal type'),
          subtitle: SegmentedButton<GoalMode>(
            segments: const [
              ButtonSegment(value: GoalMode.daily, label: Text('Daily streak')),
              ButtonSegment(value: GoalMode.weekly, label: Text('Days per week')),
            ],
            selected: {s.goalMode},
            onSelectionChanged: (v) => n.update((x) => x.copyWith(goalMode: v.first)),
          ),
        ),
        ListTile(
          title: const Text('Daily goal'),
          subtitle: Wrap(spacing: 8, children: [
            for (final g in [5, 10, 20, 40])
              ChoiceChip(
                label: Text('$g ${s.goalUnit == GoalUnit.cards ? 'cards' : 'min'}'),
                selected: s.dailyGoal == g,
                onSelected: (_) => n.update((x) => x.copyWith(dailyGoal: g)),
              ),
            ChoiceChip(
              label: Text(s.goalUnit == GoalUnit.cards ? 'Count minutes instead' : 'Count cards instead'),
              selected: false,
              onSelected: (_) => n.update((x) => x.copyWith(goalUnit: x.goalUnit == GoalUnit.cards ? GoalUnit.minutes : GoalUnit.cards)),
            ),
          ]),
        ),
        if (s.goalMode == GoalMode.weekly)
          _SliderTile(
            label: 'Days per week',
            value: s.weeklyDays.toDouble(),
            min: 2,
            max: 7,
            divisions: 5,
            display: '${s.weeklyDays}',
            onChanged: (v) => n.update((x) => x.copyWith(weeklyDays: v.round())),
          ),
        SwitchListTile(
          title: const Text('Daily reminder'),
          subtitle: Text(s.reminderEnabled
              ? 'At ${TimeOfDay(hour: s.reminderHour, minute: s.reminderMinute).format(context)} · never during 10 pm–8 am'
              : 'Off'),
          value: s.reminderEnabled,
          onChanged: (v) async {
            n.update((x) => x.copyWith(reminderEnabled: v));
            if (v) await ReminderService.instance.requestPermission();
            await reschedule(ref.read(settingsProvider));
          },
        ),
        if (s.reminderEnabled)
          ListTile(
            title: const Text('Reminder time'),
            trailing: const Icon(Icons.schedule),
            onTap: () async {
              final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: s.reminderHour, minute: s.reminderMinute));
              if (t == null) return;
              if (ReminderService.isQuietHour(t.hour)) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('That’s during quiet hours (10 pm–8 am). Pick another time.')));
                }
                return;
              }
              n.update((x) => x.copyWith(reminderHour: t.hour, reminderMinute: t.minute));
              await reschedule(ref.read(settingsProvider));
            },
          ),
        ListTile(
          title: const Text('Habit anchor'),
          subtitle: Text(s.habitAnchor.isEmpty ? 'Not set' : s.habitAnchor),
          trailing: const Icon(Icons.edit_outlined),
          onTap: () async {
            final c = TextEditingController(text: s.habitAnchor);
            final v = await showDialog<String>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('After I…'),
                content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(hintText: 'have my morning tea')),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                  FilledButton(onPressed: () => Navigator.pop(context, c.text.trim()), child: const Text('Save')),
                ],
              ),
            );
            if (v == null) return;
            n.update((x) => x.copyWith(habitAnchor: v));
            await reschedule(ref.read(settingsProvider));
          },
        ),
        header('Comfort & privacy'),
        SwitchListTile(
          title: const Text('Left-handed layout'),
          value: s.leftHanded,
          onChanged: (v) => n.update((x) => x.copyWith(leftHanded: v)),
        ),
        SwitchListTile(
          title: const Text('Hide leaderboards and comparisons'),
          value: s.hideLeaderboards,
          onChanged: (v) => n.update((x) => x.copyWith(hideLeaderboards: v)),
        ),
        ListTile(
          title: const Text('Display name'),
          subtitle: Text(s.displayName),
          trailing: const Icon(Icons.edit_outlined),
          onTap: () async {
            final c = TextEditingController(text: s.displayName == 'Reader' ? '' : s.displayName);
            final v = await showDialog<String>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Your name'),
                content: TextField(controller: c, autofocus: true),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                  FilledButton(onPressed: () => Navigator.pop(context, c.text.trim()), child: const Text('Save')),
                ],
              ),
            );
            if (v != null) n.update((x) => x.copyWith(displayName: v.isEmpty ? 'Reader' : v));
          },
        ),
        header('AI plan'),
        RadioGroup<Tier>(
          groupValue: s.tier,
          onChanged: (t) => n.update((x) => x.copyWith(tier: t)),
          child: Column(children: [
            for (final t in Tier.values)
              RadioListTile<Tier>(
                value: t,
                title: Text(switch (t) {
                  Tier.free => 'Free: on-device cards',
                  Tier.plus => 'Plus: Claude Haiku cards',
                  Tier.pro => 'Pro: Claude Sonnet cards',
                  Tier.scholar => 'Scholar: Claude Opus cards',
                }),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            bookreelApi.isEmpty
                ? 'AI cards need the BookReel server. This build has none configured, so on-device cards are used.'
                : 'Billing is not live yet: choosing a plan here only switches which AI model the server uses.',
            style: theme.textTheme.bodySmall,
          ),
        ),
        header('About'),
        ListTile(
          title: const Text('Open-source licenses'),
          subtitle: const Text('Fonts (OFL), WordNet, wordfreq (CC BY-SA 4.0)'),
          onTap: () => showLicensePage(context: context, applicationName: 'BookReel'),
        ),
        const SizedBox(height: 32),
      ]),
    );
  }
}

class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.onChanged,
    this.help,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final String? help;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Row(children: [Expanded(child: Text(label)), Text(display)]),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Slider(value: value.clamp(min, max), min: min, max: max, divisions: divisions, label: display, onChanged: onChanged),
        if (help != null) Text(help!),
      ]),
    );
  }
}
