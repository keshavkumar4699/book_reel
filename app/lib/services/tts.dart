import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Thin wrapper over Android TTS; safe to call when the engine is missing.
class Tts {
  Tts._();
  static final instance = Tts._();

  FlutterTts? _tts;
  VoidCallback? _onDone;

  FlutterTts _engine() {
    final t = _tts ??= FlutterTts();
    t.setCompletionHandler(() => _onDone?.call());
    return t;
  }

  Future<void> speak(String text, {VoidCallback? onDone}) async {
    _onDone = onDone;
    try {
      final t = _engine();
      await t.setSpeechRate(0.48);
      await t.speak(text);
    } catch (e) {
      debugPrint('TTS unavailable: $e');
      _onDone = null;
    }
  }

  Future<void> stop() async {
    _onDone = null;
    try {
      await _tts?.stop();
    } catch (_) {}
  }
}
