import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/habit/habit_engine.dart';
import '../../core/segmentation/rule_segmenter.dart';
import '../../core/text/lexicon.dart';
import '../../data/ai_client.dart';
import '../../data/settings.dart';
import '../../data/settings_provider.dart';
import '../../data/api_client.dart';
import '../../services/account.dart';
import '../../services/billing.dart';
import '../../services/mood.dart';
import '../../services/on_device_ai.dart';
import '../../services/read_aloud.dart';
import '../../services/scene_sound.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';
import '../../ui/vibes.dart';
import '../reader/goal_setup_sheet.dart';
import '../social/safety.dart';

/// Settings, compact (UX_DESIGN.md Revision 6): one short list where each row
/// shows its current value and opens a focused sheet. Simple on/off options
/// switch in place.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final ai = ref.watch(onDeviceAiProvider);
    final style = vibeStyles[s.vibe]!;
    final auto = s.autoScene && s.tier.paid && s.vibe != Vibe.paper;
    final time = MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay(hour: s.reminderHour, minute: s.reminderMinute),
        alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context));

    return KitPage(
      title: 'Settings',
      children: [
        KitGroup(label: 'App', children: [
          KitRow(
            icon: switch (s.appearance) {
              AppAppearance.system => Icons.brightness_auto_rounded,
              AppAppearance.light => Icons.light_mode_rounded,
              AppAppearance.dark => Icons.dark_mode_rounded,
            },
            title: 'Appearance',
            value: s.appearance.label,
            onTap: () => showKitSheet<void>(context,
                title: 'Appearance', subtitle: 'For every screen except the reader, which wears its scene', builder: (_) => const AppearanceSettings()),
          ),
        ]),
        KitGroup(label: 'Reading', divided: true, children: [
          KitRow(
            emoji: auto ? '✨' : style.emoji,
            title: 'Scene',
            value: auto ? 'Auto' : style.label,
            onTap: () => showKitSheet<void>(context, title: 'Scene', subtitle: 'The world behind your reels', builder: (_) => const SceneSettings()),
          ),
          KitRow(
            icon: Icons.mood_rounded,
            title: 'Mood',
            value: !s.moodScenes
                ? 'Off'
                : auto
                    ? 'The story picks'
                    : s.moodAsk == MoodAsk.never
                        ? 'On · not asking'
                        : 'On',
            onTap: () => showKitSheet<void>(context,
                title: 'Mood', subtitle: 'Your scene, picked from how you feel', builder: (_) => const MoodSettings()),
          ),
          KitRow(
            icon: s.sceneSound ? Icons.volume_up_rounded : Icons.volume_off_rounded,
            title: 'Scene sound',
            value: s.sceneSound ? 'On · ${(s.sceneSoundVolume * 100).round()}%' : 'Off',
            onTap: () => showKitSheet<void>(context, title: 'Scene sound', builder: (_) => const SoundSettings()),
          ),
          KitRow(
            icon: Icons.record_voice_over_rounded,
            title: 'Read aloud',
            value: s.naturalVoice
                ? 'Natural · ${speechVoices.where((v) => v.id == s.voiceName).firstOrNull?.label ?? 'Heart'}'
                : 'Phone voice',
            onTap: () => showKitSheet<void>(context, title: 'Read aloud', builder: (_) => const VoiceSettings()),
          ),
          KitRow(
            icon: Icons.text_fields_rounded,
            title: 'Text & theme',
            value: '${_fontName(s.font)} · ${s.fontSize.round()}',
            onTap: () => showKitSheet<void>(context, title: 'Text & theme', builder: (_) => const TextSettings()),
          ),
          KitRow(
            icon: Icons.view_agenda_rounded,
            title: 'Cards',
            value: '${_lengthName(s.cardLength)} · ${_levelName(s.readingLevel)}',
            onTap: () => showKitSheet<void>(context, title: 'Cards', builder: (_) => const CardSettings()),
          ),
          // Paid plans get the same help from Claude.
          if (!s.tier.paid)
            KitRow(
              icon: Icons.auto_awesome_rounded,
              title: 'On-device AI',
              value: switch (ai.phase) {
                LocalAiPhase.checking => '…',
                LocalAiPhase.unsupported => 'Not on this phone',
                LocalAiPhase.absent => 'Off',
                LocalAiPhase.downloading => 'Downloading ${ai.progress}%',
                LocalAiPhase.ready => s.onDeviceAi ? 'On · ${ai.model?.name ?? ''}' : 'Paused',
                LocalAiPhase.failed => 'Needs attention',
              },
              onTap: () => showKitSheet<void>(context,
                  title: 'On-device AI',
                  subtitle: 'Recaps, quick checks and word meanings, written on your phone',
                  builder: (_) => const OnDeviceAiSettings()),
            ),
        ]),
        KitGroup(label: 'Habit', divided: true, children: [
          KitRow(
            icon: Icons.flag_rounded,
            title: 'Daily goal',
            value: '${s.goal.dailyTarget} ${s.goalUnit == GoalUnit.cards ? 'cards' : 'min'}${s.reminderEnabled ? ' · $time' : ''}',
            onTap: () => showGoalSheet(context),
          ),
        ]),
        KitGroup(label: 'Comfort & privacy', divided: true, children: [
          KitSwitchRow(
            icon: Icons.back_hand_rounded,
            title: 'Left-handed layout',
            value: s.leftHanded,
            onChanged: (v) => n.update((x) => x.copyWith(leftHanded: v)),
          ),
          KitSwitchRow(
            icon: Icons.visibility_off_rounded,
            title: 'Hide leaderboards',
            subtitle: 'No rankings or comparisons',
            value: s.hideLeaderboards,
            onChanged: (v) => n.update((x) => x.copyWith(hideLeaderboards: v)),
          ),
          if (ref.watch(apiProvider).enabled)
            KitRow(
              icon: Icons.block_rounded,
              title: 'Blocked readers',
              onTap: () => showKitSheet<void>(context,
                  title: 'Blocked readers', subtitle: 'They can’t find, follow or comment on you', builder: (_) => const BlockedReaders()),
            ),
          if (bookreelApi.isNotEmpty)
            KitSwitchRow(
              icon: s.online ? Icons.cloud_rounded : Icons.cloud_off_rounded,
              title: 'Online features',
              subtitle: s.online ? 'Following, the feed, sync, AI cards and share links' : 'Off: everything stays on this phone',
              value: s.online,
              onChanged: (v) => n.update((x) => x.copyWith(online: v)),
            ),
        ]),
        KitGroup(label: 'You', divided: true, children: [
          KitRow(
            icon: Icons.badge_rounded,
            title: 'Display name',
            value: s.displayName,
            onTap: () async {
              final v = await showKitPrompt(context,
                  title: 'Your name', initial: s.displayName == 'Reader' ? '' : s.displayName, capitalization: TextCapitalization.words);
              if (v != null) n.update((x) => x.copyWith(displayName: v.isEmpty ? 'Reader' : v));
            },
          ),
          KitRow(
            icon: Icons.workspace_premium_rounded,
            title: 'Plan',
            value: s.tier.paid ? '${s.tier.label} · ${s.tier.model}' : 'Free',
            onTap: () => showKitSheet<void>(context, title: 'Plan', subtitle: 'Each plan reads your books with a stronger model', builder: (_) => const PlanPicker()),
          ),
          KitRow(
            icon: Icons.download_rounded,
            title: 'Download my data',
            subtitle: 'Everything Cloro keeps about you, as one file',
            chevron: false,
            onTap: () => _downloadData(context, ref),
          ),
          if (ref.watch(apiProvider).enabled)
            KitRow(
              icon: Icons.delete_forever_rounded,
              title: 'Delete account',
              destructive: true,
              chevron: false,
              onTap: () => _deleteAccount(context, ref),
            ),
        ]),
        KitGroup(label: 'About', divided: true, children: [
          KitRow(
            icon: Icons.description_rounded,
            title: 'Licences',
            subtitle: 'Fonts (OFL), scene sounds, WordNet, wordfreq',
            onTap: () => context.push('/licenses'),
          ),
        ]),
      ],
    );
  }
}

/// The Free plan's on-device model: what it does, whether this phone can run
/// it, the download, and switching it off or removing it.
class OnDeviceAiSettings extends ConsumerStatefulWidget {
  const OnDeviceAiSettings({super.key});

  @override
  ConsumerState<OnDeviceAiSettings> createState() => _OnDeviceAiSettingsState();
}

class _OnDeviceAiSettingsState extends ConsumerState<OnDeviceAiSettings> {
  LocalModelOption? _choice;

  static int _gb(int bytes) => (bytes / (1024 * 1024 * 1024)).ceil();

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    final ai = ref.watch(onDeviceAiProvider);
    final s = ref.watch(settingsProvider);
    final ctl = ref.read(onDeviceAiProvider.notifier);
    final choice = _choice ?? ai.model ?? localModels.first;
    Widget column(List<Widget> children) =>
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text(
            'A small AI model on your phone writes a recap and a quick check every few minutes of reading, a teaser '
            'for each chapter, and what a tapped word means in its sentence. It\'s free and private: your books never '
            'leave your phone, and it works offline.',
            style: kit.caption,
          ),
          const SizedBox(height: 14),
          ...children,
        ]);

    switch (ai.phase) {
      case LocalAiPhase.checking:
        return column([const Center(child: KitSpinner())]);
      case LocalAiPhase.unsupported:
        return column([
          KitPanel(child: Text(ai.message ?? 'This phone can\'t run it.', style: kit.body)),
          const SizedBox(height: 10),
          Text('Free reading keeps working with on-device rules.', style: kit.caption),
        ]);
      case LocalAiPhase.downloading:
        final m = ai.model!;
        return column([
          Text('Downloading ${m.name}… ${ai.progress}%', style: kit.strong),
          const SizedBox(height: 10),
          KitProgress(value: ai.progress / 100),
          const SizedBox(height: 10),
          Text('${m.sizeLabel} in all. Keep reading: it switches on when it\'s done.', style: kit.caption),
          const SizedBox(height: 14),
          KitButton.secondary(label: 'Cancel', expand: true, onPressed: ctl.cancelDownload),
        ]);
      case LocalAiPhase.ready:
        final m = ai.model!;
        return column([
          KitGroup(children: [
            KitSwitchRow(
              icon: Icons.auto_awesome_rounded,
              title: 'Use on-device AI',
              subtitle: '${m.name} · ${m.sizeLabel} on your phone',
              value: s.onDeviceAi,
              onChanged: (v) => ref.read(settingsProvider.notifier).update((x) => x.copyWith(onDeviceAi: v)),
            ),
          ]),
          const SizedBox(height: 12),
          KitButton(
            label: 'Remove model (frees ${m.sizeLabel})',
            kind: KitButtonKind.danger,
            expand: true,
            onPressed: () async {
              final ok = await showKitConfirm(context,
                  title: 'Remove ${m.name}?', message: 'You can download it again any time.', confirm: 'Remove', destructive: true);
              if (ok) await ctl.remove();
            },
          ),
        ]);
      case LocalAiPhase.absent:
      case LocalAiPhase.failed:
        final installed = localModelById(s.localModel);
        return column([
          if (ai.phase == LocalAiPhase.failed && ai.message != null) ...[
            KitPanel(child: Text(ai.message!, style: kit.body)),
            const SizedBox(height: 12),
          ],
          if (ai.phase == LocalAiPhase.failed && installed != null) ...[
            // Downloaded, but it would not load.
            KitButton(label: 'Try again', expand: true, onPressed: ctl.retry),
            const SizedBox(height: 8),
            KitButton.secondary(label: 'Remove model', expand: true, onPressed: ctl.remove),
          ] else ...[
            KitGroup(children: [
              for (final o in localModels)
                KitRow(
                  title: o.name,
                  subtitle: ai.fits(o)
                      ? '${o.sizeLabel} · ${o.blurb}'
                      : '${o.sizeLabel} · Needs a phone with ${_gb(o.minRamBytes)} GB of memory or more.',
                  selected: choice.id == o.id,
                  chevron: false,
                  onTap: ai.fits(o) ? () => setState(() => _choice = o) : null,
                ),
            ]),
            const SizedBox(height: 10),
            Text('A one-time download (Wi-Fi is best). Open model weights under the ${choice.licence} licence.', style: kit.caption),
            const SizedBox(height: 14),
            KitButton(
              label: 'Download · ${choice.sizeLabel}',
              icon: Icons.download_rounded,
              expand: true,
              onPressed: ai.fits(choice) ? () => ctl.download(choice) : null,
            ),
          ],
        ]);
    }
  }
}

/// System default, light or dark for the screens outside the reader.
class AppearanceSettings extends ConsumerWidget {
  const AppearanceSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    return KitGroup(children: [
      for (final a in AppAppearance.values)
        KitRow(
          icon: switch (a) {
            AppAppearance.system => Icons.brightness_auto_rounded,
            AppAppearance.light => Icons.light_mode_rounded,
            AppAppearance.dark => Icons.dark_mode_rounded,
          },
          title: a.label,
          subtitle: a == AppAppearance.system ? 'Follow the phone’s light or dark mode' : null,
          selected: s.appearance == a,
          chevron: false,
          onTap: () {
            ref.read(settingsProvider.notifier).update((x) => x.copyWith(appearance: a));
            // The sheet keeps the colours it opened with; close it so the
            // whole screen shows the new look at once.
            Navigator.of(context).pop();
          },
        ),
    ]);
  }
}

String _fontName(ReadingFont f) => switch (f) {
      ReadingFont.book => "Book's own fonts",
      ReadingFont.literata => 'Literata',
      ReadingFont.atkinson => 'Atkinson Hyperlegible',
      ReadingFont.system => 'System font',
    };

String _lengthName(CardLength l) => switch (l) {
      CardLength.snack => 'Snack',
      CardLength.bite => 'Bite',
      CardLength.standard => 'Standard',
      CardLength.deep => 'Deep',
    };

String _levelName(ReadingLevel l) => switch (l) {
      ReadingLevel.beginner => 'Beginner words',
      ReadingLevel.intermediate => 'Middle words',
      ReadingLevel.advanced => 'Advanced words',
    };

String _capital(String s) => s[0].toUpperCase() + s.substring(1);

/// Label, value and slider.
class _SliderField extends StatelessWidget {
  const _SliderField({
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
  final String Function(double) display;
  final ValueChanged<double> onChanged;
  final String? help;

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(label, style: kit.strong)),
          Text(display(value), style: kit.strong),
        ]),
        KitSlider(value: value, min: min, max: max, divisions: divisions, semanticLabel: label, format: display, onChanged: onChanged),
        if (help != null) Text(help!, style: kit.caption),
      ]),
    );
  }
}

/// Scene picker, Auto and motion.
class SceneSettings extends ConsumerWidget {
  const SceneSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kit = Kit.of(context);
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final paid = s.tier.paid;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      VibePickerRow(
        selected: s.vibe,
        autoSelected: paid && s.autoScene && s.vibe != Vibe.paper,
        onAuto: paid ? () => n.update((x) => x.copyWith(autoScene: true)) : null,
        onSelected: (v) => n.update((x) => x.copyWith(vibe: v, autoScene: false)),
      ),
      const SizedBox(height: 6),
      Text(paid ? 'Auto lets the AI pick the scene that fits each chapter.' : 'Auto (AI-picked scenes) comes with every paid plan.',
          style: kit.caption),
      const SizedBox(height: 14),
      KitGroup(divided: true, children: [
        KitSwitchRow(
          icon: Icons.animation_rounded,
          title: 'Moving scenes',
          subtitle: 'Gentle motion. Off when the phone’s “Remove animations” is on.',
          value: s.animatedBackground,
          onChanged: (v) => n.update((x) => x.copyWith(animatedBackground: v)),
        ),
      ]),
    ]);
  }
}

/// Mood scenes: on/off, when to ask, and what Cloro has learnt so far.
class MoodSettings extends ConsumerWidget {
  const MoodSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kit = Kit.of(context);
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final mood = ref.watch(moodProvider);
    final learning = ref.read(moodProvider.notifier).learning;
    final answers = mood.answers.length;
    final story = s.autoScene && s.tier.paid;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      KitGroup(children: [
        KitSwitchRow(
          icon: Icons.mood_rounded,
          title: 'Pick my scene from my mood',
          subtitle: story ? 'Auto scenes are on: the story picks for now.' : null,
          value: s.moodScenes,
          onChanged: (v) => n.update((x) => x.copyWith(moodScenes: v)),
        ),
      ]),
      const SizedBox(height: 12),
      Text('Ask how I’m feeling', style: kit.heading.copyWith(fontSize: 15.5)),
      const SizedBox(height: 8),
      KitSegmented<MoodAsk>(
        values: MoodAsk.values,
        selected: s.moodAsk,
        label: (a) => a.label,
        onChanged: (a) => n.update((x) => x.copyWith(moodAsk: a)),
      ),
      const SizedBox(height: 12),
      Text(
        learning
            ? 'Learning: $answers of 15 answers. Cloro asks at most every 3 hours, then picks your mood itself.'
            : 'Cloro knows your habit now: Gemma picks your mood${mood.current != null ? ' (now: ${mood.current!.emoji} ${mood.current!.label})' : ''}, '
                'with a check-in about once a week. Tap “change” on the chip to correct it.',
        style: kit.caption,
      ),
      const SizedBox(height: 8),
      Text('Only your mood log is used (when, mood, minutes read), never your book’s text.', style: kit.caption),
    ]);
  }
}

/// The scene's ambient sound.
class SoundSettings extends ConsumerWidget {
  const SoundSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kit = Kit.of(context);
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text(
        'Each scene has its own calm sound: ${sceneSoundLabels[s.vibe]!.toLowerCase()} for ${vibeStyles[s.vibe]!.label}. '
        'Turn it off (or tap the speaker while reading) to play your own music.',
        style: kit.caption,
      ),
      const SizedBox(height: 12),
      KitGroup(divided: true, children: [
        KitSwitchRow(
          icon: Icons.graphic_eq_rounded,
          title: 'Play the scene’s sound',
          value: s.sceneSound,
          onChanged: (v) => n.update((x) => x.copyWith(sceneSound: v)),
        ),
      ]),
      if (s.sceneSound)
        _SliderField(
          label: 'Volume',
          value: s.sceneSoundVolume,
          min: 0.05,
          max: 1,
          divisions: 19,
          display: (v) => '${(v * 100).round()}%',
          onChanged: (v) {
            n.update((x) => x.copyWith(sceneSoundVolume: v));
            ref.read(sceneSoundProvider.notifier).applyVolume();
          },
        ),
    ]);
  }
}

/// The read-aloud voice: natural AI voice or the phone's, which voice, speed.
class VoiceSettings extends ConsumerWidget {
  const VoiceSettings({super.key});

  static const sample = 'Alice was beginning to get very tired of sitting by her sister on the bank, and of having nothing to do.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kit = Kit.of(context);
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final server = ref.watch(apiProvider).enabled;
    void play() => ref.read(readAloudProvider).speak(sample, onDone: () {});
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      KitSegmented<bool>(
        values: const [true, false],
        selected: s.naturalVoice,
        label: (v) => v ? 'Natural AI voice' : 'Phone voice',
        onChanged: (v) => n.update((x) => x.copyWith(naturalVoice: v)),
      ),
      const SizedBox(height: 10),
      Text(
        s.naturalVoice
            ? server
                ? 'A neural voice that sounds close to a person reading. Each passage is kept on your phone, so '
                    'listening again is instant and works offline. Free: about 25 minutes of new listening a day; '
                    'paid plans: hours.'
                : 'The natural voice comes from the Cloro server, which this build doesn\'t have yet, so your '
                    'phone\'s most natural voice reads for now.'
            : 'Your phone\'s own voice: works offline and costs nothing. We pick the most natural one it has installed.',
        style: kit.caption,
      ),
      if (s.naturalVoice) ...[
        const SizedBox(height: 12),
        KitGroup(divided: true, children: [
          for (final v in speechVoices)
            KitRow(
              title: v.label,
              subtitle: v.description,
              selected: s.voiceName == v.id,
              chevron: false,
              onTap: () {
                n.update((x) => x.copyWith(voiceName: v.id));
                play();
              },
            ),
        ]),
      ],
      _SliderField(
        label: 'Speed',
        value: s.voiceSpeed,
        min: 0.8,
        max: 1.3,
        divisions: 10,
        display: (v) => '${v.toStringAsFixed(2).replaceFirst(RegExp(r'0\$'), '')}×',
        onChanged: (v) => n.update((x) => x.copyWith(voiceSpeed: double.parse(v.toStringAsFixed(2)))),
      ),
      const SizedBox(height: 14),
      KitButton.secondary(label: 'Play a sample', icon: Icons.play_arrow_rounded, expand: true, onPressed: play),
    ]);
  }
}

/// Font, size, spacing and the paper theme, with a live preview.
class TextSettings extends ConsumerWidget {
  const TextSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kit = Kit.of(context);
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final preview = ReadingTheme.of(effectiveReadingTheme(s, MediaQuery.platformBrightnessOf(context)));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      // Live preview of the reading text.
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: preview.background, borderRadius: BorderRadius.circular(18), border: Border.all(color: kit.stroke)),
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
      const SizedBox(height: 16),
      Text('FONT', style: kit.label),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final f in ReadingFont.values)
          KitChip(label: _fontName(f), selected: s.font == f, onTap: () => n.update((x) => x.copyWith(font: f))),
      ]),
      const SizedBox(height: 6),
      Text(
        switch (s.font) {
          ReadingFont.book => s.tier.paid
              ? 'Each book gets fonts that fit it, chosen by the AI from its genre and opening pages.'
              : 'Each book gets fonts that fit its genre (fantasy, mystery, sci-fi, romance, non-fiction…).',
          ReadingFont.atkinson => 'Designed for low vision; used for every book.',
          _ => 'Used for every book.',
        },
        style: kit.caption,
      ),
      _SliderField(
        label: 'Text size',
        value: s.fontSize,
        min: 14,
        max: 32,
        divisions: 18,
        display: (v) => '${v.round()}',
        onChanged: (v) => n.update((x) => x.copyWith(fontSize: v)),
      ),
      _SliderField(
        label: 'Line spacing',
        value: s.lineHeight,
        min: 1.2,
        max: 2.0,
        divisions: 8,
        display: (v) => v.toStringAsFixed(1),
        onChanged: (v) => n.update((x) => x.copyWith(lineHeight: v)),
      ),
      _SliderField(
        label: 'Letter spacing',
        help: 'Wider spacing can make reading easier, especially with dyslexia.',
        value: s.letterSpacing,
        min: 0,
        max: 2,
        divisions: 8,
        display: (v) => v.toStringAsFixed(2),
        onChanged: (v) => n.update((x) => x.copyWith(letterSpacing: v, wordSpacing: v * 2)),
      ),
      const SizedBox(height: 18),
      Text('PAPER THEME', style: kit.label),
      const SizedBox(height: 2),
      Text('For the Paper scene and page mode', style: kit.caption),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final t in ReadingThemeId.values)
          KitChip(label: _capital(t.name), selected: s.theme == t, onTap: () => n.update((x) => x.copyWith(theme: t))),
      ]),
      const SizedBox(height: 12),
      KitGroup(divided: true, children: [
        KitSwitchRow(
          icon: Icons.dark_mode_rounded,
          title: 'Dark with the phone',
          subtitle: 'Use the dark theme when the phone is in dark mode',
          value: s.followSystemDark,
          onChanged: (v) => n.update((x) => x.copyWith(followSystemDark: v)),
        ),
      ]),
    ]);
  }
}

/// How books become cards.
class CardSettings extends ConsumerWidget {
  const CardSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kit = Kit.of(context);
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    Widget label(String t) => Padding(padding: const EdgeInsets.only(top: 14, bottom: 8), child: Text(t, style: kit.label));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      label('CARD LENGTH'),
      KitSegmented<CardLength>(
        values: CardLength.values,
        selected: s.cardLength,
        label: _lengthName,
        onChanged: (v) => n.update((x) => x.copyWith(cardLength: v)),
      ),
      label('KEY POINTS'),
      KitSegmented<KeyPointStyle>(
        values: KeyPointStyle.values,
        selected: s.keyPointStyle,
        label: (v) => _capital(v.name),
        onChanged: (v) => n.update((x) => x.copyWith(keyPointStyle: v)),
      ),
      label('VOCABULARY LEVEL'),
      KitSegmented<ReadingLevel>(
        values: ReadingLevel.values,
        selected: s.readingLevel,
        label: (v) => switch (v) {
          ReadingLevel.beginner => 'Beginner',
          ReadingLevel.intermediate => 'Middle',
          ReadingLevel.advanced => 'Advanced',
        },
        onChanged: (v) => n.update((x) => x.copyWith(readingLevel: v)),
      ),
      const SizedBox(height: 16),
      KitGroup(divided: true, children: [
        KitSwitchRow(
          icon: Icons.format_underlined_rounded,
          title: 'Underline hard words',
          value: s.underlineHardWords,
          onChanged: (v) => n.update((x) => x.copyWith(underlineHardWords: v)),
        ),
        KitSwitchRow(
          icon: Icons.title_rounded,
          title: 'AI card titles',
          subtitle: 'Shown when AI cards are available',
          value: s.showAiTitles,
          onChanged: (v) => n.update((x) => x.copyWith(showAiTitles: v)),
        ),
        KitSwitchRow(
          icon: Icons.quiz_rounded,
          title: 'Quick-check cards',
          subtitle: 'A one-tap recall check every ~10 cards',
          value: s.recallCards,
          onChanged: (v) => n.update((x) => x.copyWith(recallCards: v)),
        ),
        KitSwitchRow(
          icon: Icons.psychology_alt_rounded,
          title: 'Reflect cards',
          subtitle: 'One question at the end of each chapter',
          value: s.reflectCards,
          onChanged: (v) => n.update((x) => x.copyWith(reflectCards: v)),
        ),
      ]),
    ]);
  }
}

/// The five plans, cheapest first (DESIGN.md §6.1). With Play Billing live,
/// each plan shows Play's local price and subscribes; otherwise (development
/// builds) picking a plan just switches the AI model.
class PlanPicker extends ConsumerStatefulWidget {
  const PlanPicker({super.key});

  static String blurb(Tier t) => switch (t) {
        Tier.free => 'Cards cut on your phone. Every scene, sound and streak.',
        Tier.lite => 'Claude Haiku reads your books: AI emphasis, Auto scenes and book fonts.',
        Tier.plus => 'Claude Sonnet: sharper cuts, recaps and quick checks.',
        Tier.pro => 'Claude Opus: the deepest reading of dense and difficult books.',
        Tier.scholar => 'Claude Fable: our most capable model, for the books that matter most.',
      };

  @override
  ConsumerState<PlanPicker> createState() => _PlanPickerState();
}

class _PlanPickerState extends ConsumerState<PlanPicker> {
  bool _yearly = false;

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    final s = ref.watch(settingsProvider);
    final billing = ref.watch(billingProvider);
    final store = ref.read(billingProvider.notifier);
    if (!billing.live) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        KitGroup(children: [
          for (final t in Tier.values)
            KitRow(
              title: t.paid ? '${t.label} · \$${t.usdPerMonth.toStringAsFixed(2)}/mo' : 'Free',
              subtitle: PlanPicker.blurb(t),
              selected: s.tier == t,
              chevron: false,
              onTap: () => ref.read(settingsProvider.notifier).update((x) => x.copyWith(tier: t)),
            ),
        ]),
        const SizedBox(height: 10),
        Text(
          bookreelApi.isEmpty
              ? 'AI cards need the Cloro server. This build has none configured, so on-device cards are used.'
              : 'Google Play subscriptions aren\u2019t set up for this build, so choosing a plan here only switches '
                  'which AI model the server uses. US prices; local prices are shown at checkout.',
          style: kit.caption,
        ),
      ]);
    }
    final expires = billing.expiresAt;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      KitSegmented<bool>(
        values: const [false, true],
        selected: _yearly,
        label: (y) => y ? 'Yearly' : 'Monthly',
        onChanged: (y) => setState(() => _yearly = y),
      ),
      const SizedBox(height: 12),
      KitGroup(divided: true, children: [
        KitRow(title: 'Free', subtitle: PlanPicker.blurb(Tier.free), selected: s.tier == Tier.free, chevron: false),
        for (final t in Tier.values.where((t) => t.paid))
          Builder(builder: (context) {
            final offer = billing.offer(t, yearly: _yearly);
            final current = s.tier == t;
            return KitRow(
              title: offer == null ? t.label : '${t.label} · ${offer.price}/${_yearly ? 'yr' : 'mo'}',
              subtitle: [PlanPicker.blurb(t), if (offer?.trial != null && !current) 'Try it free for ${offer!.trial}.'].join(' '),
              selected: current,
              chevron: false,
              trailing: current || offer == null ? null : Text(s.tier.paid ? 'Switch' : 'Subscribe', style: kit.strong.copyWith(decoration: TextDecoration.underline)),
              onTap: current || offer == null || billing.busy ? null : () => store.buy(offer),
            );
          }),
      ]),
      if (billing.message != null) ...[
        const SizedBox(height: 10),
        Text(billing.message!, style: kit.caption.copyWith(color: kit.ink)),
      ],
      const SizedBox(height: 10),
      Text(
        [
          if (s.tier.paid && expires != null)
            'Your ${s.tier.label} plan renews or ends on ${MaterialLocalizations.of(context).formatMediumDate(expires.toLocal())}.',
          'Subscriptions renew automatically until you cancel in Google Play. Switching plans credits the time left on the old one.',
        ].join(' '),
        style: kit.caption,
      ),
      const SizedBox(height: 6),
      KitButton.ghost(label: 'Restore purchases', icon: Icons.restore_rounded, onPressed: billing.busy ? null : store.restore),
    ]);
  }
}

/// Download my data: a JSON file with what's on this phone and what the
/// server keeps, handed to the share sheet (save it, email it…).
Future<void> _downloadData(BuildContext context, WidgetRef ref) async {
  showKitToast(context, 'Preparing your data…', icon: Icons.download_rounded, duration: const Duration(milliseconds: 1400));
  try {
    final file = await ref.read(accountProvider).exportFile();
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'application/json')], subject: 'My Cloro data'));
  } catch (_) {
    if (context.mounted) showKitToast(context, 'Couldn’t prepare the file. Try again.', icon: Icons.error_outline_rounded);
  }
}

/// Delete account: erased from the server at once; this phone keeps its books
/// and notes, and online features turn off.
Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
  final ok = await showKitConfirm(
    context,
    title: 'Delete your account?',
    message: 'This erases your profile, followers and following, reading activity, comments, kudos, synced notes and share links '
        'from Cloro’s servers. It can’t be undone.\n\n'
        'Your books and notes stay on this phone, and online features turn off. '
        'Subscriptions are managed in Google Play. You can download your data first.',
    confirm: 'Delete',
    destructive: true,
  );
  if (!ok || !context.mounted) return;
  try {
    await ref.read(accountProvider).deleteAccount();
    if (context.mounted) showKitToast(context, 'Your account is deleted', icon: Icons.check_rounded);
  } catch (_) {
    if (context.mounted) {
      showKitToast(context, 'Couldn’t reach Cloro, so nothing was deleted. Try again.', icon: Icons.cloud_off_rounded);
    }
  }
}
