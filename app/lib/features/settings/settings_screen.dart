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
import '../../services/on_device_ai.dart';
import '../../services/read_aloud.dart';
import '../../services/local_voice.dart';
import '../../services/music.dart';
import '../reader/add_pictures.dart';
import '../../ui/backdrops.dart';
import '../../l10n/l10n.dart';
import '../../ui/haptics.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';
import '../../ui/typography.dart';
import '../reader/goal_setup_sheet.dart';
import '../social/safety.dart';
import 'feedback_sheet.dart';

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
    final pictures = ref.watch(backdropsProvider).value;
    final ownPictures = pictures != null && pictures.any((b) => b.isYours);
    final time = MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay(hour: s.reminderHour, minute: s.reminderMinute),
        alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context));

    return KitPage(
      title: tr('Settings'),
      children: [
        KitGroup(label: tr('App'), children: [
          KitRow(
            icon: switch (s.appearance) {
              AppAppearance.system => Icons.brightness_auto_rounded,
              AppAppearance.light => Icons.light_mode_rounded,
              AppAppearance.dark => Icons.dark_mode_rounded,
            },
            hue: KitHue.neutral,
            title: tr('Appearance'),
            value: s.appearance.label,
            onTap: () => showKitSheet<void>(context,
                title: tr('Appearance'), subtitle: tr('For every screen except the reader, which wears its scene'), builder: (_) => const AppearanceSettings()),
          ),
          KitRow(
            icon: Icons.translate_rounded,
            hue: KitHue.neutral,
            title: tr('Language'),
            value: s.language.isEmpty ? tr('Phone’s language') : languageFor(s.language).name,
            onTap: () => showKitSheet<void>(context, title: tr('Language'), builder: (_) => const LanguageSettings()),
          ),
        ]),
        KitGroup(label: tr('Reading'), divided: true, children: [
          KitRow(
            icon: Icons.image_outlined,
            hue: KitHue.activity,
            title: tr('Backgrounds'),
            value: ownPictures ? tr('Your pictures') : tr('Pictures and scenes'),
            onTap: () => showKitSheet<void>(context,
                title: tr('Backgrounds'), subtitle: tr('A different one each time you open a book'), builder: (_) => const BackgroundSettings()),
          ),
          KitRow(
            icon: s.music ? Icons.music_note_rounded : Icons.music_off_rounded,
            hue: KitHue.words,
            title: tr('Music'),
            value: s.music ? tr('On · {percent}%', {'percent': (s.musicVolume * 100).round()}) : tr('Off'),
            onTap: () => showKitSheet<void>(context, title: tr('Music'), builder: (_) => const MusicSettings()),
          ),
          KitRow(
            icon: Icons.record_voice_over_rounded,
            hue: KitHue.words,
            title: tr('Read aloud'),
            value: s.naturalVoice
                ? tr('Natural · {voice}', {'voice': speechVoices.where((v) => v.id == s.voiceName).firstOrNull?.label ?? 'Heart'})
                : tr('Phone voice'),
            onTap: () => showKitSheet<void>(context, title: tr('Read aloud'), builder: (_) => const VoiceSettings()),
          ),
          KitRow(
            icon: Icons.text_fields_rounded,
            hue: KitHue.activity,
            title: tr('Text & theme'),
            value: '${_fontName(s.font)} · ${s.fontSize.round()}',
            onTap: () => showKitSheet<void>(context, title: tr('Text & theme'), builder: (_) => const TextSettings()),
          ),
          KitRow(
            icon: Icons.view_agenda_rounded,
            hue: KitHue.activity,
            title: tr('Cards'),
            value: '${_lengthName(s.cardLength)} · ${_levelName(s.readingLevel)}',
            onTap: () => showKitSheet<void>(context, title: tr('Cards'), builder: (_) => const CardSettings()),
          ),
          // Paid plans get the same help from Claude.
          if (!s.tier.paid)
            KitRow(
              icon: Icons.auto_awesome_rounded,
              hue: KitHue.notes,
            title: tr('On-device AI'),
              value: switch (ai.phase) {
                LocalAiPhase.checking => '…',
                LocalAiPhase.unsupported => tr('Not on this phone'),
                LocalAiPhase.absent => tr('Off'),
                LocalAiPhase.downloading => tr('Downloading {percent}%', {'percent': ai.progress}),
                LocalAiPhase.ready => s.onDeviceAi ? tr('On · {model}', {'model': ai.model?.name ?? ''}) : tr('Paused'),
                LocalAiPhase.failed => tr('Needs attention'),
              },
              onTap: () => showKitSheet<void>(context,
                  title: tr('On-device AI'),
                  subtitle: tr('Recaps, quick checks and word meanings, written on your phone'),
                  builder: (_) => const OnDeviceAiSettings()),
            ),
        ]),
        KitGroup(label: tr('Habit'), divided: true, children: [
          KitRow(
            icon: Icons.flag_rounded,
            hue: KitHue.growth,
            title: tr('Daily goal'),
            value: '${s.goalUnit == GoalUnit.cards ? trn(s.goal.dailyTarget, '{n} card', '{n} cards') : tr('{n} min', {'n': s.goal.dailyTarget})}${s.reminderEnabled ? ' · $time' : ''}',
            onTap: () => showGoalSheet(context),
          ),
        ]),
        KitGroup(label: tr('Comfort & privacy'), divided: true, children: [
          KitSwitchRow(
            icon: Icons.back_hand_rounded,
            hue: KitHue.neutral,
            title: tr('Left-handed layout'),
            value: s.leftHanded,
            onChanged: (v) => n.update((x) => x.copyWith(leftHanded: v)),
          ),
          KitSwitchRow(
            icon: Icons.vibration_rounded,
            hue: KitHue.neutral,
            title: tr('Vibration'),
            subtitle: tr('A light tap when you choose, like, save or finish'),
            value: s.haptics,
            onChanged: (v) => n.update((x) => x.copyWith(haptics: v)),
          ),
          KitSwitchRow(
            icon: Icons.visibility_off_rounded,
            hue: KitHue.people,
            title: tr('Hide leaderboards'),
            subtitle: tr('No rankings or comparisons'),
            value: s.hideLeaderboards,
            onChanged: (v) => n.update((x) => x.copyWith(hideLeaderboards: v)),
          ),
          if (ref.watch(apiProvider).enabled)
            KitRow(
              icon: Icons.block_rounded,
              hue: KitHue.people,
            title: tr('Blocked readers'),
              onTap: () => showKitSheet<void>(context,
                  title: tr('Blocked readers'), subtitle: tr('They can’t find, follow or comment on you'), builder: (_) => const BlockedReaders()),
            ),
          if (bookreelApi.isNotEmpty)
            KitSwitchRow(
              icon: Icons.bug_report_outlined,
              hue: KitHue.neutral,
            title: tr('Send crash reports'),
              subtitle: tr('What went wrong and where, never your books'),
              value: s.crashReports,
              onChanged: (v) => n.update((x) => x.copyWith(crashReports: v)),
            ),
          if (bookreelApi.isNotEmpty)
            KitSwitchRow(
              icon: s.online ? Icons.cloud_rounded : Icons.cloud_off_rounded,
              hue: KitHue.people,
            title: tr('Online features'),
              subtitle: s.online ? tr('Following, the feed, sync, AI cards and share links') : tr('Off: everything stays on this phone'),
              value: s.online,
              onChanged: (v) => n.update((x) => x.copyWith(online: v)),
            ),
        ]),
        KitGroup(label: tr('You'), divided: true, children: [
          KitRow(
            icon: Icons.badge_rounded,
            hue: KitHue.people,
            title: tr('Display name'),
            value: s.displayName,
            onTap: () async {
              final v = await showKitPrompt(context,
                  title: tr('Your name'), initial: s.displayName == 'Reader' ? '' : s.displayName, capitalization: TextCapitalization.words);
              if (v != null) n.update((x) => x.copyWith(displayName: v.isEmpty ? 'Reader' : v));
            },
          ),
          KitRow(
            icon: Icons.workspace_premium_rounded,
            hue: KitHue.notes,
            title: tr('Plan'),
            value: s.tier.paid ? '${s.tier.label} · ${s.tier.model}' : tr('Free'),
            onTap: () => showKitSheet<void>(context, title: tr('Plan'), subtitle: tr('Each plan reads your books with a stronger model'), builder: (_) => const PlanPicker()),
          ),
          KitRow(
            icon: Icons.download_rounded,
            hue: KitHue.neutral,
            title: tr('Download my data'),
            subtitle: tr('Everything Cloro keeps about you, as one file'),
            chevron: false,
            onTap: () => _downloadData(context, ref),
          ),
          if (ref.watch(apiProvider).enabled)
            KitRow(
              icon: Icons.delete_forever_rounded,
              title: tr('Delete account'),
              destructive: true,
              chevron: false,
              onTap: () => _deleteAccount(context, ref),
            ),
        ]),
        KitGroup(label: tr('About'), divided: true, children: [
          KitRow(
            icon: Icons.mail_outline_rounded,
            hue: KitHue.people,
            title: tr('Send feedback'),
            subtitle: tr('An idea, a problem, anything'),
            onTap: () => showFeedbackSheet(context),
          ),
          KitRow(icon: Icons.privacy_tip_outlined, hue: KitHue.neutral, title: tr('Privacy policy'), onTap: () => context.push('/legal/privacy')),
          KitRow(icon: Icons.gavel_rounded, hue: KitHue.neutral, title: tr('Terms of use'), onTap: () => context.push('/legal/terms')),
          KitRow(
            icon: Icons.description_rounded,
            hue: KitHue.neutral,
            title: tr('Licences'),
            subtitle: tr('Fonts (OFL), music, WordNet, wordfreq'),
            onTap: () => context.push('/licenses'),
          ),
          KitRow(icon: Icons.info_outline_rounded, hue: KitHue.neutral, title: tr('Version'), value: appVersionLabel()),
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
            tr('A small AI model on your phone writes a recap and a quick check every few minutes of reading, a teaser '
            'for each chapter, and what a tapped word means in its sentence. It\'s free and private: your books never '
            'leave your phone, and it works offline.'),
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
          KitPanel(child: Text(ai.message ?? tr('This phone can\'t run it.'), style: kit.body)),
          const SizedBox(height: 10),
          Text(tr('Free reading keeps working with on-device rules.'), style: kit.caption),
        ]);
      case LocalAiPhase.downloading:
        final m = ai.model!;
        return column([
          Text(tr('Downloading {model}… {percent}%', {'model': m.name, 'percent': ai.progress}), style: kit.strong),
          const SizedBox(height: 10),
          KitProgress(value: ai.progress / 100),
          const SizedBox(height: 10),
          Text(tr('{size} in all. Keep reading: it switches on when it\'s done.', {'size': m.sizeLabel}), style: kit.caption),
          const SizedBox(height: 14),
          KitButton.secondary(label: tr('Cancel'), expand: true, onPressed: ctl.cancelDownload),
        ]);
      case LocalAiPhase.ready:
        final m = ai.model!;
        return column([
          KitGroup(children: [
            KitSwitchRow(
              icon: Icons.auto_awesome_rounded,
              title: tr('Use on-device AI'),
              subtitle: tr('{model} · {size} on your phone', {'model': m.name, 'size': m.sizeLabel}),
              value: s.onDeviceAi,
              onChanged: (v) => ref.read(settingsProvider.notifier).update((x) => x.copyWith(onDeviceAi: v)),
            ),
          ]),
          const SizedBox(height: 12),
          KitButton(
            label: tr('Remove model (frees {size})', {'size': m.sizeLabel}),
            kind: KitButtonKind.danger,
            expand: true,
            onPressed: () async {
              final ok = await showKitConfirm(context,
                  title: tr('Remove {model}?', {'model': m.name}), message: tr('You can download it again any time.'), confirm: tr('Remove'), destructive: true);
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
            KitButton(label: tr('Try again'), expand: true, onPressed: ctl.retry),
            const SizedBox(height: 8),
            KitButton.secondary(label: tr('Remove model'), expand: true, onPressed: ctl.remove),
          ] else ...[
            KitGroup(children: [
              for (final o in localModels)
                KitRow(
                  title: o.name,
                  subtitle: ai.fits(o)
                      ? '${o.sizeLabel} · ${tr(o.blurb)}'
                      : '${o.sizeLabel} · ${tr('Needs a phone with {gb} GB of memory or more.', {'gb': _gb(o.minRamBytes)})}',
                  selected: choice.id == o.id,
                  chevron: false,
                  onTap: ai.fits(o) ? () => setState(() => _choice = o) : null,
                ),
            ]),
            const SizedBox(height: 10),
            Text(tr('A one-time download (Wi-Fi is best). Open model weights under the {licence} licence.', {'licence': choice.licence}), style: kit.caption),
            const SizedBox(height: 14),
            KitButton(
              label: tr('Download · {size}', {'size': choice.sizeLabel}),
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
          subtitle: a == AppAppearance.system ? tr('Follow the phone’s light or dark mode') : null,
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

/// One line on what a font is good for.
String _fontNote(ReadingFont f) => switch (f) {
      ReadingFont.book => '',
      ReadingFont.literata => tr('Made for long reading on screens (Google Play Books).'),
      ReadingFont.merriweather => tr('Sturdy and open, designed for reading on screens.'),
      ReadingFont.sourceSerif => tr('A crisp modern serif in the old-style tradition.'),
      ReadingFont.ebGaramond => tr('The classic book face, after Garamond’s 16th-century type.'),
      ReadingFont.crimsonPro => tr('An elegant book serif, light on the page.'),
      ReadingFont.lora => tr('A calligraphic serif, warm for stories.'),
      ReadingFont.libreBaskerville => tr('Baskerville’s classic, tuned for screens.'),
      ReadingFont.alegreya => tr('A lively literary serif with a calligraphic rhythm.'),
      ReadingFont.newsreader => tr('Made for long reads on screens, newspaper-style.'),
      ReadingFont.bitter => tr('A friendly slab serif, very clear at small sizes.'),
      ReadingFont.inter => tr('A clean, neutral sans.'),
      ReadingFont.lexend => tr('A sans made to reduce visual stress and help reading fluency.'),
      ReadingFont.nunito => tr('A soft, rounded sans.'),
      ReadingFont.atkinson => tr('Designed for low vision: every letter easy to tell apart.'),
      ReadingFont.openDyslexic => tr('Weighted letters some readers with dyslexia find easier.'),
      ReadingFont.system => tr('Your phone’s own font.'),
    };

String _fontName(ReadingFont f) => switch (f) {
      ReadingFont.book => "Book's own fonts",
      ReadingFont.literata => 'Literata',
      ReadingFont.merriweather => 'Merriweather',
      ReadingFont.sourceSerif => 'Source Serif',
      ReadingFont.ebGaramond => 'EB Garamond',
      ReadingFont.crimsonPro => 'Crimson Pro',
      ReadingFont.lora => 'Lora',
      ReadingFont.libreBaskerville => 'Libre Baskerville',
      ReadingFont.alegreya => 'Alegreya',
      ReadingFont.newsreader => 'Newsreader',
      ReadingFont.bitter => 'Bitter',
      ReadingFont.inter => 'Inter',
      ReadingFont.lexend => 'Lexend',
      ReadingFont.nunito => 'Nunito',
      ReadingFont.atkinson => 'Atkinson Hyperlegible',
      ReadingFont.openDyslexic => 'OpenDyslexic',
      ReadingFont.system => tr('System font'),
    };

String _lengthName(CardLength l) => switch (l) {
      CardLength.snack => tr('Snack'),
      CardLength.bite => tr('Bite'),
      CardLength.standard => tr('Standard'),
      CardLength.deep => tr('Deep'),
    };

String _levelName(ReadingLevel l) => switch (l) {
      ReadingLevel.beginner => tr('Beginner words'),
      ReadingLevel.intermediate => tr('Middle words'),
      ReadingLevel.advanced => tr('Advanced words'),
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

/// Where the backgrounds come from, and whether painted scenes move.
class BackgroundSettings extends ConsumerWidget {
  const BackgroundSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kit = Kit.of(context);
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final all = ref.watch(backdropsProvider).value ?? const <Backdrop>[];
    final yours = all.where((b) => b.isYours).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text(
        tr('Each book opens on a picture or scene picked at random. While reading, tap the screen and pick another from the row at the top, '
            'or tap + there to add pictures from your phone. A long press on one you added removes it.'),
        style: kit.caption,
      ),
      const SizedBox(height: 14),
      KitButton.secondary(
        label: tr('Add pictures from your phone'),
        icon: Icons.add_photo_alternate_outlined,
        expand: true,
        onPressed: () async {
          final added = await addPicturesFromPhone(context, ref);
          if (added != null && added.isNotEmpty && context.mounted) {
            showKitToast(context, trn(added.length, 'Picture added', '{n} pictures added'), icon: Icons.image_outlined);
          }
        },
      ),
      if (yours > 0) ...[
        const SizedBox(height: 6),
        Text(trn(yours, '{n} picture of yours', '{n} pictures of yours'), textAlign: TextAlign.center, style: kit.caption),
      ],
      const SizedBox(height: 14),
      KitGroup(divided: true, children: [
        KitSwitchRow(
          icon: Icons.animation_rounded,
          title: tr('Moving scenes'),
          subtitle: tr('Gentle motion. Off when the phone’s “Remove animations” is on.'),
          value: s.animatedBackground,
          onChanged: (v) => n.update((x) => x.copyWith(animatedBackground: v)),
        ),
      ]),
    ]);
  }
}

/// Music while reading: on or off, and how loud.
class MusicSettings extends ConsumerWidget {
  const MusicSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kit = Kit.of(context);
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final tracks = ref.watch(tracksProvider).value ?? const <Track>[];
    final own = tracks.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text(
        own > 0
            ? trn(own, 'Your track plays while you read. While reading, tap the screen for pause and play at the bottom.',
                'Each book starts one of your {n} tracks at random, then plays on through them. While reading, tap the screen for previous, pause and next at the bottom.')
            : tr('There’s no music in the app yet: tracks added to its sounds folder play while you read.'),
        style: kit.caption,
      ),
      const SizedBox(height: 12),
      KitGroup(divided: true, children: [
        KitSwitchRow(
          icon: Icons.music_note_rounded,
          title: tr('Play music while reading'),
          subtitle: s.music ? null : tr('Books open in silence; play is a tap away.'),
          value: s.music,
          onChanged: (v) => n.update((x) => x.copyWith(music: v)),
        ),
      ]),
      _SliderField(
        label: tr('Volume'),
        value: s.musicVolume,
        min: 0.05,
        max: 1,
        divisions: 19,
        display: (v) => '${(v * 100).round()}%',
        onChanged: (v) {
          n.update((x) => x.copyWith(musicVolume: v));
          ref.read(musicProvider.notifier).applyVolume();
        },
      ),
    ]);
  }
}

/// The natural voice on this phone: download it, see it come down, or
/// remove it.
class _LocalVoicePanel extends ConsumerWidget {
  const _LocalVoicePanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kit = Kit.of(context);
    final local = ref.watch(localVoiceProvider);
    final voice = ref.read(localVoiceProvider.notifier);
    switch (local.phase) {
      case LocalVoicePhase.checking:
        return const SizedBox.shrink();
      case LocalVoicePhase.ready:
        return Row(children: [
          Icon(Icons.offline_pin_rounded, size: 20, color: kit.ink),
          const SizedBox(width: 8),
          Expanded(child: Text(tr('On this phone · {size}', {'size': formatBytes(LocalVoiceModel.installedBytes)}), style: kit.strong.copyWith(fontSize: 14))),
          KitButton.ghost(label: tr('Remove'), compact: true, onPressed: voice.remove),
        ]);
      case LocalVoicePhase.downloading:
      case LocalVoicePhase.unpacking:
        final unpacking = local.phase == LocalVoicePhase.unpacking;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Text(unpacking ? tr('Getting the voice ready…') : tr('Downloading the voice · {percent}%', {'percent': local.progress}),
                  style: kit.strong.copyWith(fontSize: 14)),
            ),
            if (!unpacking) KitButton.ghost(label: tr('Cancel'), compact: true, onPressed: voice.cancelDownload),
          ]),
          const SizedBox(height: 8),
          KitProgress(value: unpacking ? 1 : local.progress / 100, height: 4, color: kit.ink, track: kit.field),
        ]);
      case LocalVoicePhase.absent:
      case LocalVoicePhase.failed:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (local.message != null) ...[
            Text(local.message!, style: kit.caption.copyWith(color: kit.danger)),
            const SizedBox(height: 8),
          ],
          KitButton(
            label: tr('Download the natural voice ({size})', {'size': localVoiceDownloadSize}),
            icon: Icons.download_rounded,
            expand: true,
            onPressed: voice.download,
          ),
        ]);
    }
  }
}

/// The read-aloud voice: natural AI voice or the phone's, which voice, speed.
class VoiceSettings extends ConsumerWidget {
  const VoiceSettings({super.key});

  // Read in English: the natural voices are English voices.
  static const sample = 'Alice was beginning to get very tired of sitting by her sister on the bank, and of having nothing to do.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kit = Kit.of(context);
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final server = ref.watch(apiProvider).enabled;
    final local = ref.watch(localVoiceProvider);
    void play() => ref.read(readAloudProvider).sample(sample);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      KitSegmented<bool>(
        values: const [true, false],
        selected: s.naturalVoice,
        label: (v) => v ? tr('Natural AI voice') : tr('Phone voice'),
        onChanged: (v) => n.update((x) => x.copyWith(naturalVoice: v)),
      ),
      const SizedBox(height: 10),
      Text(
        !s.naturalVoice
            ? tr('Your phone\'s own voice: works offline and costs nothing. We pick the most natural one it has installed.')
            : local.ready
                ? tr('A neural voice that sounds close to a person reading, running on your phone: free, unlimited and '
                    'offline. Nothing you read is sent anywhere.')
                : server
                    ? tr('A neural voice that sounds close to a person reading, from the Cloro server. Free: about 25 '
                        'minutes of new listening a day; paid plans: hours. Download it to your phone and it\'s '
                        'unlimited, offline too.')
                    : tr('A neural voice that sounds close to a person reading. Download it once ({size}) '
                        'and it runs on your phone: free, unlimited and offline. Until then, your phone\'s own voice reads.', {'size': localVoiceDownloadSize}),
        style: kit.caption,
      ),
      if (s.naturalVoice) ...[
        const SizedBox(height: 12),
        const _LocalVoicePanel(),
        const SizedBox(height: 12),
        KitGroup(divided: true, children: [
          for (final v in speechVoices)
            KitRow(
              title: v.label,
              subtitle: tr(v.description),
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
        label: tr('Speed'),
        value: s.voiceSpeed,
        min: 0.8,
        max: 1.3,
        divisions: 10,
        display: (v) => '${v.toStringAsFixed(2).replaceFirst(RegExp(r'0\$'), '')}×',
        onChanged: (v) => n.update((x) => x.copyWith(voiceSpeed: double.parse(v.toStringAsFixed(2)))),
      ),
      const SizedBox(height: 14),
      KitButton.secondary(label: tr('Play a sample'), icon: Icons.play_arrow_rounded, expand: true, onPressed: play),
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
            fontVariations: weightAxis(FontWeight.w400),
            fontSize: s.fontSize,
            height: s.lineHeight,
            letterSpacing: s.letterSpacing,
            wordSpacing: s.wordSpacing,
            color: preview.text,
          ),
        ),
      ),
      const SizedBox(height: 16),
      Text(tr('FONT'), style: kit.label),
      const SizedBox(height: 8),
      // Each font's name in its own face.
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final f in ReadingFont.values)
          KitChip(
            label: _fontName(f),
            fontFamily: f == ReadingFont.book || f == ReadingFont.system ? null : fontFamilyFor(f),
            selected: s.font == f,
            onTap: () => n.update((x) => x.copyWith(font: f)),
          ),
      ]),
      const SizedBox(height: 6),
      Text(
        s.font == ReadingFont.book
            ? (s.tier.paid
                ? tr('Each book gets fonts that fit it, chosen by the AI from its genre and opening pages.')
                : tr('Each book gets fonts that fit its genre (fantasy, mystery, sci-fi, romance, non-fiction…).'))
            : '${_fontNote(s.font)} ${tr('Used for every book.')}',
        style: kit.caption,
      ),
      _SliderField(
        label: tr('Text size'),
        value: s.fontSize,
        min: 14,
        max: 32,
        divisions: 18,
        display: (v) => '${v.round()}',
        onChanged: (v) => n.update((x) => x.copyWith(fontSize: v)),
      ),
      _SliderField(
        label: tr('Line spacing'),
        value: s.lineHeight,
        min: 1.2,
        max: 2.0,
        divisions: 8,
        display: (v) => v.toStringAsFixed(1),
        onChanged: (v) => n.update((x) => x.copyWith(lineHeight: v)),
      ),
      _SliderField(
        label: tr('Letter spacing'),
        help: tr('Wider spacing can make reading easier, especially with dyslexia.'),
        value: s.letterSpacing,
        min: 0,
        max: 2,
        divisions: 8,
        display: (v) => v.toStringAsFixed(2),
        onChanged: (v) => n.update((x) => x.copyWith(letterSpacing: v, wordSpacing: v * 2)),
      ),
      const SizedBox(height: 18),
      Text(tr('PAPER THEME'), style: kit.label),
      const SizedBox(height: 2),
      Text(tr('For the Paper scene and page mode'), style: kit.caption),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final t in ReadingThemeId.values)
          KitChip(label: _capital(t.name), selected: s.theme == t, onTap: () => n.update((x) => x.copyWith(theme: t))),
      ]),
      const SizedBox(height: 12),
      KitGroup(divided: true, children: [
        KitSwitchRow(
          icon: Icons.dark_mode_rounded,
          title: tr('Dark with the phone'),
          subtitle: tr('Use the dark theme when the phone is in dark mode'),
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
      label(tr('CARD LENGTH')),
      KitSegmented<CardLength>(
        values: CardLength.values,
        selected: s.cardLength,
        label: _lengthName,
        onChanged: (v) => n.update((x) => x.copyWith(cardLength: v)),
      ),
      label(tr('KEY POINTS')),
      KitSegmented<KeyPointStyle>(
        values: KeyPointStyle.values,
        selected: s.keyPointStyle,
        label: (v) => _capital(v.name),
        onChanged: (v) => n.update((x) => x.copyWith(keyPointStyle: v)),
      ),
      label(tr('VOCABULARY LEVEL')),
      KitSegmented<ReadingLevel>(
        values: ReadingLevel.values,
        selected: s.readingLevel,
        label: (v) => switch (v) {
          ReadingLevel.beginner => tr('Beginner'),
          ReadingLevel.intermediate => tr('Middle'),
          ReadingLevel.advanced => tr('Advanced'),
        },
        onChanged: (v) => n.update((x) => x.copyWith(readingLevel: v)),
      ),
      const SizedBox(height: 16),
      KitGroup(divided: true, children: [
        KitSwitchRow(
          icon: Icons.format_underlined_rounded,
          title: tr('Underline hard words'),
          value: s.underlineHardWords,
          onChanged: (v) => n.update((x) => x.copyWith(underlineHardWords: v)),
        ),
        KitSwitchRow(
          icon: Icons.title_rounded,
          title: tr('AI card titles'),
          subtitle: tr('Shown when AI cards are available'),
          value: s.showAiTitles,
          onChanged: (v) => n.update((x) => x.copyWith(showAiTitles: v)),
        ),
        KitSwitchRow(
          icon: Icons.quiz_rounded,
          title: tr('Quick-check cards'),
          subtitle: tr('A one-tap recall check every ~10 cards'),
          value: s.recallCards,
          onChanged: (v) => n.update((x) => x.copyWith(recallCards: v)),
        ),
        KitSwitchRow(
          icon: Icons.psychology_alt_rounded,
          title: tr('Reflect cards'),
          subtitle: tr('One question at the end of each chapter'),
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
        Tier.free => tr('Cards cut on your phone. Every scene, sound and streak.'),
        Tier.lite => tr('Claude Haiku reads your books: AI emphasis, Auto scenes and book fonts.'),
        Tier.plus => tr('Claude Sonnet: sharper cuts, recaps and quick checks.'),
        Tier.pro => tr('Claude Opus: the deepest reading of dense and difficult books.'),
        Tier.scholar => tr('Claude Fable: our most capable model, for the books that matter most.'),
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
              title: t.paid ? tr('{plan} · \${price}/mo', {'plan': t.label, 'price': t.usdPerMonth.toStringAsFixed(2)}) : tr('Free'),
              subtitle: PlanPicker.blurb(t),
              selected: s.tier == t,
              chevron: false,
              onTap: () => ref.read(settingsProvider.notifier).update((x) => x.copyWith(tier: t)),
            ),
        ]),
        const SizedBox(height: 10),
        Text(
          bookreelApi.isEmpty
              ? tr('AI cards need the Cloro server. This build has none configured, so on-device cards are used.')
              : tr('Google Play subscriptions aren\u2019t set up for this build, so choosing a plan here only switches '
                  'which AI model the server uses. US prices; local prices are shown at checkout.'),
          style: kit.caption,
        ),
      ]);
    }
    final expires = billing.expiresAt;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      KitSegmented<bool>(
        values: const [false, true],
        selected: _yearly,
        label: (y) => y ? tr('Yearly') : tr('Monthly'),
        onChanged: (y) => setState(() => _yearly = y),
      ),
      const SizedBox(height: 12),
      KitGroup(divided: true, children: [
        KitRow(title: tr('Free'), subtitle: PlanPicker.blurb(Tier.free), selected: s.tier == Tier.free, chevron: false),
        for (final t in Tier.values.where((t) => t.paid))
          Builder(builder: (context) {
            final offer = billing.offer(t, yearly: _yearly);
            final current = s.tier == t;
            return KitRow(
              title: offer == null ? t.label : (_yearly ? tr('{plan} · {price}/yr', {'plan': t.label, 'price': offer.price}) : tr('{plan} · {price}/mo', {'plan': t.label, 'price': offer.price})),
              subtitle: [PlanPicker.blurb(t), if (offer?.trial != null && !current) tr('Try it free for {trial}.', {'trial': offer!.trial})].join(' '),
              selected: current,
              chevron: false,
              trailing: current || offer == null ? null : Text(s.tier.paid ? tr('Switch') : tr('Subscribe'), style: kit.strong.copyWith(decoration: TextDecoration.underline)),
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
            tr('Your {plan} plan renews or ends on {date}.', {'plan': s.tier.label, 'date': MaterialLocalizations.of(context).formatMediumDate(expires.toLocal())}),
          tr('Subscriptions renew automatically until you cancel in Google Play. Switching plans credits the time left on the old one.'),
        ].join(' '),
        style: kit.caption,
      ),
      const SizedBox(height: 6),
      KitButton.ghost(label: tr('Restore purchases'), icon: Icons.restore_rounded, onPressed: billing.busy ? null : store.restore),
    ]);
  }
}

/// Download my data: a JSON file with what's on this phone and what the
/// server keeps, handed to the share sheet (save it, email it…).
Future<void> _downloadData(BuildContext context, WidgetRef ref) async {
  showKitToast(context, tr('Preparing your data…'), icon: Icons.download_rounded, duration: const Duration(milliseconds: 1400));
  try {
    final file = await ref.read(accountProvider).exportFile();
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'application/json')], subject: tr('My Cloro data')));
  } catch (_) {
    if (context.mounted) showKitToast(context, tr('Couldn’t prepare the file. Try again.'), icon: Icons.error_outline_rounded);
  }
}

/// Delete account: erased from the server at once; this phone keeps its books
/// and notes, and online features turn off.
Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
  final ok = await showKitConfirm(
    context,
    title: tr('Delete your account?'),
    message: tr('This erases your profile, followers and following, reading activity, comments, kudos, synced notes and share links '
        'from Cloro’s servers. It can’t be undone.\n\n'
        'Your books and notes stay on this phone, and online features turn off. '
        'Subscriptions are managed in Google Play. You can download your data first.'),
    confirm: tr('Delete'),
    destructive: true,
  );
  if (!ok || !context.mounted) return;
  try {
    await ref.read(accountProvider).deleteAccount();
    if (context.mounted) showKitToast(context, tr('Your account is deleted'), icon: Icons.check_rounded);
  } catch (_) {
    if (context.mounted) {
      showKitToast(context, tr('Couldn’t reach Cloro, so nothing was deleted. Try again.'), icon: Icons.cloud_off_rounded);
    }
  }
}

/// The app's language: the phone's (when the app has it), or one of the
/// nine, each named in its own language.
class LanguageSettings extends ConsumerWidget {
  const LanguageSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kit = Kit.of(context);
    final chosen = ref.watch(settingsProvider.select((s) => s.language));
    final phone = resolveLanguage('', WidgetsBinding.instance.platformDispatcher.locales);
    void pick(String code) {
      Haptics.select();
      ref.read(settingsProvider.notifier).update((x) => x.copyWith(language: code));
      Navigator.of(context).pop();
    }

    Widget row(String code, String title, String? subtitle) => KitRow(
          title: title,
          subtitle: subtitle,
          trailing: chosen == code ? Icon(Icons.check_rounded, color: kit.ink) : null,
          onTap: () => pick(code),
        );
    return KitGroup(divided: true, children: [
      row('', tr('Phone’s language'), languageFor(phone).name),
      for (final l in appLanguages) row(l.code, l.name, l.name == l.english ? null : l.english),
    ]);
  }
}
