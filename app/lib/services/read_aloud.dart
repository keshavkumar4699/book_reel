import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../data/api_client.dart';
import '../data/settings.dart';
import '../data/settings_provider.dart';
import 'tts.dart';

/// A natural voice offered for reading aloud (a Kokoro voice on the server).
class SpeechVoiceInfo {
  const SpeechVoiceInfo(this.id, this.label, this.description);
  final String id;
  final String label;
  final String description;
}

const speechVoices = [
  SpeechVoiceInfo('af_heart', 'Heart', 'Warm, American'),
  SpeechVoiceInfo('am_michael', 'Michael', 'Calm, American'),
  SpeechVoiceInfo('bf_emma', 'Emma', 'Clear, British'),
  SpeechVoiceInfo('bm_george', 'George', 'Deep, British'),
];

/// Plays one audio file at a time and says when it finished.
abstract class SpeechPlayer {
  Future<void> playFile(String path);
  Future<void> stop();
  Stream<void> get completed;
  Future<void> dispose();
}

class JustAudioSpeechPlayer implements SpeechPlayer {
  // Mixes with the scene sound and other apps (the scene sound ducks under it).
  final AudioPlayer _player = AudioPlayer(handleAudioSessionActivation: false);

  @override
  Stream<void> get completed => _player.processingStateStream.where((s) => s == ProcessingState.completed).map((_) {});

  @override
  Future<void> playFile(String path) async {
    await _player.setFilePath(path);
    unawaited(_player.play());
  }

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}

/// Reads reels aloud (DESIGN.md §2.4). The natural AI voice comes from the
/// BookReel server (a neural model, Kokoro by default); each passage is kept
/// on the phone, so replays are instant, free and work offline, and the next
/// reel is fetched while this one plays, so listening flows without gaps.
/// Without a server, offline or over the daily allowance, the phone's most
/// natural installed voice reads instead.
class ReadAloud {
  ReadAloud(this._ref);

  final Ref _ref;

  /// Tests replace these.
  static SpeechPlayer Function() playerFactory = JustAudioSpeechPlayer.new;
  static Future<Directory> Function() cacheRoot = getTemporaryDirectory;

  /// At most this many passages are kept (about 20–40 MB).
  static const keep = 300;

  SpeechPlayer? _playerInstance;
  StreamSubscription<void>? _done;
  VoidCallback? _onDone;
  int _turn = 0;
  DateTime? _naturalPausedUntil;
  final Map<String, Future<File>> _pending = {};

  SpeechPlayer get _player {
    final p = _playerInstance;
    if (p != null) return p;
    final created = playerFactory();
    _done = created.completed.listen((_) {
      final cb = _onDone;
      _onDone = null;
      cb?.call();
    });
    return _playerInstance = created;
  }

  /// The natural voice is in use (not paused after an error).
  bool get naturalActive {
    final s = _ref.read(settingsProvider);
    final until = _naturalPausedUntil;
    return s.naturalVoice && _ref.read(apiProvider).enabled && (until == null || DateTime.now().isAfter(until));
  }

  /// Reads [text]; [next] (the following reel) is fetched meanwhile.
  Future<void> speak(String text, {String? next, required VoidCallback onDone}) async {
    final turn = ++_turn;
    await _stopPlayback();
    final s = _ref.read(settingsProvider);
    if (naturalActive) {
      try {
        final file = await _audioFor(text, s);
        if (turn != _turn) return;
        _onDone = onDone;
        await _player.playFile(file.path);
        if (next != null && next.trim().isNotEmpty) unawaited(_audioFor(next, s).then((_) {}, onError: (_) {}));
        return;
      } on ApiException catch (e) {
        // No provider on the server (503) or today's allowance used (429).
        _naturalPausedUntil = DateTime.now().add(e.status == 429 ? const Duration(hours: 1) : const Duration(minutes: 30));
      } catch (e) {
        debugPrint('Natural voice unavailable: $e');
        _naturalPausedUntil = DateTime.now().add(const Duration(minutes: 2));
      }
      if (turn != _turn) return;
    }
    await Tts.instance.speak(text, rate: 0.5 * s.voiceSpeed, onDone: onDone);
  }

  Future<void> stop() async {
    _turn++;
    await _stopPlayback();
    await Tts.instance.stop();
  }

  Future<void> _stopPlayback() async {
    _onDone = null;
    final p = _playerInstance;
    if (p != null) await p.stop();
  }

  static String keyFor(String text, String voice, double speed) =>
      sha1.convert('$voice|${speed.toStringAsFixed(2)}|${text.trim()}'.codeUnits).toString();

  /// The passage's audio file: from the phone's cache, or fetched once.
  Future<File> _audioFor(String text, AppSettings s) {
    final key = keyFor(text, s.voiceName, s.voiceSpeed);
    // (The callback must not return the removed future: whenComplete would
    // wait on it, i.e. on itself.)
    return _pending[key] ??= _fetch(key, text, s).whenComplete(() {
      _pending.remove(key);
    });
  }

  Future<File> _fetch(String key, String text, AppSettings s) async {
    final dir = Directory('${(await cacheRoot()).path}/speech');
    final file = File('${dir.path}/$key.mp3');
    if (await file.exists()) return file;
    final bytes = await _ref.read(apiProvider).speech(text: text.trim(), voice: s.voiceName, speed: s.voiceSpeed, tier: s.tier.name);
    await dir.create(recursive: true);
    final tmp = File('${file.path}.part');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(file.path);
    unawaited(_prune(dir));
    return file;
  }

  static Future<void> _prune(Directory dir) async {
    try {
      final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.mp3')).toList();
      if (files.length <= keep) return;
      files.sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));
      for (final f in files.take(files.length - keep)) {
        f.deleteSync();
      }
    } catch (_) {}
  }

  Future<void> dispose() async {
    _turn++;
    await _done?.cancel();
    await _playerInstance?.dispose();
    _playerInstance = null;
  }
}

final readAloudProvider = Provider<ReadAloud>((ref) {
  final r = ReadAloud(ref);
  ref.onDispose(r.dispose);
  return r;
});
