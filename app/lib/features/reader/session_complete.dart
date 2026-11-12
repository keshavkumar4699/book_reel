import 'package:flutter/material.dart';

import '../../ui/kit.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

enum SessionChoice { keepReading, done, share }

/// The designed ending (peak-end rule, UX_DESIGN.md §5.3). "Keep reading" is
/// offered, never pushed; stopping is framed as success. Shown over the
/// scene the reader was reading in.
Future<SessionChoice?> showSessionComplete(
  BuildContext context, {
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
    transitionDuration: MediaQuery.of(context).disableAnimations ? Duration.zero : const Duration(milliseconds: 320),
    transitionBuilder: (context, a, _, child) => FadeTransition(opacity: CurvedAnimation(parent: a, curve: Curves.easeOutCubic), child: child),
    pageBuilder: (dialogContext, a1, a2) => InheritedTheme.captureAll(
      context,
      Builder(builder: (context) {
        final kit = Kit.of(context);
        return Material(
          type: MaterialType.transparency,
          child: DefaultTextStyle(
            style: kit.body,
            child: Stack(children: [
              // A fuller shade than in the reader: this screen is all text.
              const Positioned.fill(child: SceneBackdrop(animate: true, veil: 0.42)),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(children: [
                    const Spacer(),
                    Celebration(big: milestone != null),
                    const SizedBox(height: 12),
                    Text(milestone != null ? '$milestone-day streak!' : 'Goal done', style: kit.display),
                    const SizedBox(height: 8),
                    Text('$cards cards · ${minutes.round()} min', style: kit.heading),
                    const SizedBox(height: 4),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.local_fire_department_rounded, color: ember),
                      const SizedBox(width: 4),
                      Text('$streak-day streak', style: kit.heading),
                    ]),
                    if (ideaOfTheDay != null) ...[
                      const SizedBox(height: 32),
                      Text('YOUR IDEA OF THE DAY', style: kit.label),
                      const SizedBox(height: 10),
                      Text('“$ideaOfTheDay”',
                          textAlign: TextAlign.center,
                          maxLines: 6,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontFamily: 'Literata', fontSize: 19, height: 1.45, color: kit.ink)),
                      if (ideaSource != null) ...[
                        const SizedBox(height: 6),
                        Text(ideaSource, style: kit.caption),
                      ],
                    ],
                    const Spacer(),
                    Row(children: [
                      Expanded(
                        child: KitButton.secondary(
                          label: 'Share',
                          leading: const ShareArrowIcon(),
                          expand: true,
                          onPressed: () => Navigator.of(dialogContext).pop(SessionChoice.share),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: KitButton(
                          label: 'Keep reading',
                          expand: true,
                          onPressed: () => Navigator.of(dialogContext).pop(SessionChoice.keepReading),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    KitButton.ghost(label: 'Done for today', onPressed: () => Navigator.of(dialogContext).pop(SessionChoice.done)),
                  ]),
                ),
              ),
            ]),
          ),
        );
      }),
      to: Navigator.of(context, rootNavigator: true).context,
    ),
  );
}
