import 'package:flutter/material.dart';

import '../../services/mood.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';

/// "How are you feeling?": one flat list of moods, then "Not now". Returns
/// the mood picked, or null (Not now, or dismissed).
Future<Mood?> showMoodSheet(BuildContext context, {Mood? current}) => showKitSheet<Mood>(
      context,
      title: 'How are you feeling?',
      subtitle: 'Cloro learns when you read best and sets a scene to match.',
      builder: (context) => Column(mainAxisSize: MainAxisSize.min, children: [
        KitGroup(children: [
          for (final m in Mood.values)
            KitRow(
              emoji: m.emoji,
              title: m.label,
              selected: m == current,
              chevron: false,
              onTap: () => Navigator.of(context).pop(m),
            ),
        ]),
        KitGroup(divided: true, children: [
          KitRow(icon: Icons.schedule_rounded, title: 'Not now', chevron: false, onTap: () => Navigator.of(context).pop()),
        ]),
      ]),
    );

/// "😌 Calm · change": shown for a few seconds when Cloro picked the scene
/// from your mood. A tap corrects it.
class MoodChip extends StatelessWidget {
  const MoodChip({super.key, required this.mood, required this.visible, required this.theme, required this.onTap});

  final Mood? mood;
  final bool visible;
  final ReadingTheme theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final m = mood;
    return IgnorePointer(
      ignoring: !visible || m == null,
      child: AnimatedOpacity(
        opacity: visible && m != null ? 1 : 0,
        duration: const Duration(milliseconds: 400),
        child: m == null
            ? const SizedBox.shrink()
            : Semantics(
                button: true,
                label: 'Mood: ${m.label}. Change',
                excludeSemantics: true,
                child: GestureDetector(
                  onTap: onTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(color: theme.glass, borderRadius: BorderRadius.circular(999)),
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: '${m.emoji} ${m.label}', style: const TextStyle(fontWeight: FontWeight.w700)),
                        TextSpan(text: '  ·  change', style: TextStyle(color: theme.muted)),
                      ]),
                      style: TextStyle(color: theme.text, fontSize: 13.5),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
