import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Keeps the phone's screen on while reels are read aloud hands-free: a
/// screen that timed out would stop them turning (the app pauses), the way a
/// video player keeps it on while it plays. Asks MainActivity over
/// `app.cloro/screen`; elsewhere (tests, other platforms) it does nothing.
class ScreenAwake {
  ScreenAwake._();

  static const channel = MethodChannel('app.cloro/screen');

  static bool _on = false;

  /// Whether the screen is being kept on.
  static bool get on => _on;

  static Future<void> keep(bool on) async {
    if (on == _on) return;
    _on = on;
    try {
      await channel.invokeMethod<void>('keepOn', on);
    } on MissingPluginException {
      // No screen to keep on here.
    } catch (e) {
      debugPrint('Screen awake unavailable: $e');
    }
  }
}
