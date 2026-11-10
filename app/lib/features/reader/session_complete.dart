import 'package:flutter/material.dart';

import '../../data/settings.dart';
import '../../ui/theme.dart';
import '../../ui/vibes.dart';
import '../../ui/widgets.dart';

enum SessionChoice { keepReading, done, share }

/// The designed ending (peak-end rule, UX_DESIGN.md §5.3). "Keep reading" is
/// offered, never pushed; stopping is framed as success.
Future<SessionChoice?> showSessionComplete(
  BuildContext context, {
  Vibe vibe = Vibe.paper,
  required int cards,
  required double minutes,
  required int streak,
  int? milestone,
  String? ideaOfTheDay,
  String? ideaSource,
}) {
  return showGeneralDialog<SessionChoice>(
    context: context,
    barrierDismissible: false,
    transitionDuration: MediaQuery.of(context).disableAnimations ? Duration.zero : const Duration(milliseconds: 280),
    pageBuilder: (context, a1, a2) {
      final theme = vibe == Vibe.paper ? Theme.of(context) : buildAppTheme(brightness: Brightness.dark);
      return Theme(
        data: theme,
        child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(children: [
          Positioned.fill(child: VibeBackground(vibe: vibe, paperColor: theme.colorScheme.surface)),
          if (vibe != Vibe.paper) const Positioned.fill(child: ColoredBox(color: Color(0x66000000))),
          SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(children: [
              const Spacer(),
              Celebration(big: milestone != null),
              const SizedBox(height: 12),
              Text(milestone != null ? '$milestone-day streak!' : 'Goal done',
                  style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text('$cards cards · ${minutes.round()} min', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.local_fire_department, color: ember),
                const SizedBox(width: 4),
                Text('$streak-day streak', style: theme.textTheme.titleMedium),
              ]),
              if (ideaOfTheDay != null) ...[
                const SizedBox(height: 32),
                Text('Your idea of the day', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                Text('“$ideaOfTheDay”',
                    textAlign: TextAlign.center,
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'Literata', fontSize: 19, height: 1.45)),
                if (ideaSource != null) ...[
                  const SizedBox(height: 6),
                  Text(ideaSource, style: theme.textTheme.bodySmall),
                ],
              ],
              const Spacer(),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pop(SessionChoice.share),
                    icon: const Icon(Icons.ios_share),
                    label: const Text('Share'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(SessionChoice.keepReading),
                    child: const Text('Keep reading'),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(SessionChoice.done),
                child: const Text('Done for today'),
              ),
            ]),
          ),
        ),
        ]),
      ),
      );
    },
  );
}
