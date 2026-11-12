import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Picks the most natural installed voice for [language] (e.g. "en"): the
/// highest quality first, then the phone's own country, preferring voices
/// that work offline. Voices that are listed but not downloaded are skipped.
Map<String, String>? bestPhoneVoice(List<Map<String, String>> voices, {required String language, String? country}) {
  int quality(String? q) => switch (q) {
        'very high' => 5,
        'high' => 4,
        'normal' => 3,
        'low' => 2,
        'very low' => 1,
        _ => 0,
      };
  Map<String, String>? best;
  var bestScore = -1;
  for (final v in voices) {
    final locale = (v['locale'] ?? '').replaceAll('_', '-').toLowerCase();
    if (!locale.startsWith(language.toLowerCase())) continue;
    if ((v['features'] ?? '').contains('notInstalled')) continue;
    final score = quality(v['quality']) * 10 +
        (country != null && locale.endsWith('-${country.toLowerCase()}') ? 5 : 0) +
        (v['network_required'] == '1' ? 0 : 2) +
        (v['latency'] == 'very high' ? -3 : 0);
    if (score > bestScore) {
      best = v;
      bestScore = score;
    }
  }
  return best;
}

/// The phone's own text-to-speech, with its most natural installed voice.
/// Safe to call when the engine is missing.
class Tts {
  Tts._();
  static final instance = Tts._();

  FlutterTts? _tts;
  VoidCallback? _onDone;
  bool _voiceChosen = false;

  Future<FlutterTts> _engine() async {
    final t = _tts ??= FlutterTts();
    t.setCompletionHandler(() {
      final cb = _onDone;
      _onDone = null;
      cb?.call();
    });
    if (!_voiceChosen) {
      _voiceChosen = true;
      try {
        final raw = (await t.getVoices as List?) ?? const [];
        final voices = [for (final v in raw) if (v is Map) v.map((k, x) => MapEntry('$k', '$x'))];
        final locale = PlatformDispatcher.instance.locale;
        final best = bestPhoneVoice(voices, language: locale.languageCode == 'en' ? 'en' : locale.languageCode, country: locale.countryCode) ??
            bestPhoneVoice(voices, language: 'en');
        if (best != null) await t.setVoice({'name': best['name']!, 'locale': best['locale']!});
      } catch (e) {
        debugPrint('TTS voices unavailable: $e');
      }
    }
    return t;
  }

  /// Speaks [text]; [rate] 0.5 is the phone's normal speed.
  Future<void> speak(String text, {double rate = 0.5, VoidCallback? onDone}) async {
    _onDone = onDone;
    try {
      final t = await _engine();
      await t.setSpeechRate(rate.clamp(0.3, 0.8));
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
