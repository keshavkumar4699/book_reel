import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Vibration you can feel when you choose, like, save or finish something.
///
/// Each kind maps to feedback Android actually plays: Flutter's "selection"
/// and "medium" types become the system's clock tick and keyboard tap,
/// which many Android phones play very faintly or not at all. So a choice
/// is a crisp key click there, and a success is two clicks in quick
/// succession, which every Android version plays. (The system's own "touch
/// feedback" setting still applies, and so does the Vibration switch in
/// Settings, mirrored in [enabled].)
abstract final class Haptics {
  /// The Vibration setting.
  static bool enabled = true;

  /// A faint detent as something moves on: the next reel, a highlight
  /// handle passing a word, a wheel turning. Faint on purpose (on many
  /// Android phones, nothing): it comes often.
  static void tick() => _play(HapticFeedback.selectionClick);

  /// A choice: a chip, a tab, a switch, a segment, a picture, a day.
  static void select() => _play(HapticFeedback.lightImpact, apple: HapticFeedback.selectionClick);

  /// A tap that does something: like, save, follow, kudos, a button.
  static void tap() => _play(HapticFeedback.lightImpact);

  /// A firm press: a long press, a highlight started, a swipe that acts.
  static void press() => _play(HapticFeedback.vibrate, apple: HapticFeedback.mediumImpact);

  /// Something done: today's goal, a book finished, a streak milestone.
  static void success() {
    if (!enabled) return;
    if (_apple) {
      unawaited(HapticFeedback.successNotification());
      return;
    }
    unawaited(HapticFeedback.lightImpact());
    Timer(const Duration(milliseconds: 110), () {
      if (enabled) unawaited(HapticFeedback.lightImpact());
    });
  }

  static bool get _apple => defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS;

  static void _play(Future<void> Function() android, {Future<void> Function()? apple}) {
    if (!enabled) return;
    unawaited((_apple ? (apple ?? android) : android)());
  }
}
