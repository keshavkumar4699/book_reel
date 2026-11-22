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
import 'local_voice.dart';
import 'tts.dart';

/// A natural voice offered for reading aloud (a Kokoro voice, on the phone
/// or on the server).
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

/// A passage being turned into audio before it can play: since when, and
/// about how long it should take (learned from how fast earlier passages
/// were made), for the reader's progress bar.
@immutable
class SpeechWait {
  const SpeechWait({required this.chars, required this.expected});

  /// How long the passage is.
  final int chars;
  final Duration expected;
}

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

/// Reads reels aloud (DESIGN.md §2.4) with the most natural voice it has:
/// 1. the natural voice on the phone (Kokoro, once downloaded): free,
///    unlimited and offline. It speaks a few sentences at a time, so a reel
///    starts as soon as its first sentence is ready;
/// 2. the natural voice from the Cloro server, the same model;
/// 3. the phone's most natural installed voice.
/// Each passage's audio is kept on the phone, so replays are instant. While
/// a reel plays, the reels around it are made ready, nearest first (the next
/// two, then the one before), so moving on or back plays at once. When a
/// reel isn't ready yet, [waiting] says so, for the reader's progress bar.
class ReadAloud {
  ReadAloud(this._ref);

  final Ref _ref;

  /// Tests replace these.
  static SpeechPlayer Function() playerFactory = JustAudioSpeechPlayer.new;
  static Future<Directory> Function() cacheRoot = getTemporaryDirectory;

  /// At most this many passages are kept (about 20–40 MB).
  static const keep = 300;

  /// A passage is being turned into audio before it can play (null when
  /// nothing is waiting).
  final ValueNotifier<SpeechWait?> waiting = ValueNotifier(null);

  /// About how many characters a second each voice turns into audio,
  /// learned as it goes (a phone and a connection differ a lot).
  double _localRate = 30, _serverRate = 160;

  /// A wait shorter than this shows no progress bar (no flash for audio
  /// that's nearly ready).
  static Duration showWaitAfter = const Duration(milliseconds: 150);

  SpeechPlayer? _playerInstance;
  StreamSubscription<void>? _done;
  VoidCallback? _onDone;
  int _turn = 0;
  DateTime? _naturalPausedUntil;
  DateTime? _localPausedUntil;
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

  /// The natural voice on the phone is in use (downloaded, and not paused
  /// after an error).
  bool get localActive {
    final s = _ref.read(settingsProvider);
    final until = _localPausedUntil;
    return s.naturalVoice && _ref.read(localVoiceProvider).ready && (until == null || DateTime.now().isAfter(until));
  }

  /// The natural voice from the server is in use (not paused after an error).
  bool get naturalActive {
    final s = _ref.read(settingsProvider);
    final until = _naturalPausedUntil;
    return s.naturalVoice && _ref.read(apiProvider).enabled && (until == null || DateTime.now().isAfter(until));
  }

  /// Reads [text]. Meanwhile the reels around it are made ready, nearest
  /// first: [ahead] (the next ones, in order), then [behind] (the one before).
  Future<void> speak(String text, {List<String> ahead = const [], String? behind, required VoidCallback onDone}) async {
    final turn = ++_turn;
    waiting.value = null;
    await _stopPlayback();
    final s = _ref.read(settingsProvider);
    final around = [
      for (final t in [...ahead, ?behind])
        if (t.trim().isNotEmpty) t,
    ];
    if (localActive) {
      try {
        await _speakLocal(turn, text, around, onDone, s);
        return;
      } on VoiceLoadFailure catch (e) {
        _ref.read(localVoiceProvider.notifier).markBroken(e);
      } catch (e) {
        debugPrint('On-device voice unavailable: $e');
        _localPausedUntil = DateTime.now().add(const Duration(minutes: 5));
      }
      if (turn != _turn) return;
    }
    if (naturalActive) {
      try {
        final file = await _waitFor(turn, _audioFor(text, s), text.length, local: false);
        if (turn != _turn) return;
        _onDone = onDone;
        await _player.playFile(file.path);
        // The reels around, one at a time while this one plays.
        unawaited(() async {
          for (final t in around) {
            if (turn != _turn) return;
            await _audioFor(t, s);
          }
        }().catchError((Object _) {}));
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
    waiting.value = null;
    await _stopPlayback();
    await Tts.instance.stop();
  }

  Future<void> _stopPlayback() async {
    _onDone = null;
    final p = _playerInstance;
    if (p != null) await p.stop();
  }

  /// Speaks [text] with the voice on the phone, part by part: each part is
  /// made while the one before plays. Once the last is made, the reels
  /// [around] it are made, part by part and nearest first, in the time left
  /// (one at a time, so the reel you move to never queues behind much). A
  /// part that can't be made hands the rest to the phone's own voice.
  Future<void> _speakLocal(int turn, String text, List<String> around, VoidCallback onDone, AppSettings s) async {
    final parts = speechParts(text);
    if (parts.isEmpty) return onDone();
    final made = <int, Future<File>>{};
    final allMade = Completer<void>();
    Future<File> make(int i) => made[i] ??= _localAudioFor(parts[i], s)
      ..then((_) {
        if (i == parts.length - 1 && !allMade.isCompleted) allMade.complete();
      }, onError: (Object _) {});

    unawaited(() async {
      await allMade.future;
      for (final t in around) {
        for (final part in speechParts(t)) {
          if (turn != _turn) return;
          await _localAudioFor(part, s);
        }
      }
    }().catchError((Object _) {}));

    Future<void> playFrom(int i) async {
      final file = await _waitFor(turn, make(i), parts[i].length, local: true);
      if (turn != _turn) return;
      if (i + 1 < parts.length) {
        make(i + 1).ignore();
        _onDone = () => unawaited(playFrom(i + 1).catchError((Object e) {
              debugPrint('On-device voice stopped: $e');
              if (turn == _turn) unawaited(Tts.instance.speak(parts.sublist(i + 1).join(' '), rate: 0.5 * s.voiceSpeed, onDone: onDone));
            }));
      } else {
        _onDone = onDone;
      }
      await _player.playFile(file.path);
    }

    await playFrom(0);
  }

  /// Waits for [work] (a passage of [chars] characters being made); if it
  /// takes more than a moment, [waiting] shows it with the time it should
  /// take.
  Future<File> _waitFor(int turn, Future<File> work, int chars, {required bool local}) async {
    var settled = false;
    final show = Timer(showWaitAfter, () {
      if (settled || turn != _turn) return;
      final seconds = chars / (local ? _localRate : _serverRate);
      waiting.value = SpeechWait(chars: chars, expected: Duration(milliseconds: (seconds * 1000).round().clamp(600, 60000)));
    });
    try {
      return await work;
    } finally {
      settled = true;
      show.cancel();
      if (turn == _turn) waiting.value = null;
    }
  }

  /// How fast a voice made a passage, folded into what it's expected to do.
  void _learn({required bool local, required int chars, required Duration took}) {
    if (took < const Duration(milliseconds: 80) || chars < 20) return;
    final rate = chars / (took.inMicroseconds / 1e6);
    if (local) {
      _localRate = _localRate * 0.6 + rate * 0.4;
    } else {
      _serverRate = _serverRate * 0.6 + rate * 0.4;
    }
  }

  Future<File> _localAudioFor(String text, AppSettings s) {
    final key = keyFor(text, 'local:${s.voiceName}', s.voiceSpeed);
    return _pending[key] ??= _makeLocal(key, text, s).whenComplete(() {
      _pending.remove(key);
    });
  }

  Future<File> _makeLocal(String key, String text, AppSettings s) async {
    final dir = Directory('${(await cacheRoot()).path}/speech');
    final file = File('${dir.path}/$key.wav');
    if (await file.exists()) return file;
    await dir.create(recursive: true);
    final watch = Stopwatch()..start();
    await _ref.read(localSpeechProvider).synthesize(text: text, speaker: localSpeakerFor(s.voiceName), speed: s.voiceSpeed, path: file.path);
    _learn(local: true, chars: text.length, took: watch.elapsed);
    unawaited(_prune(dir));
    return file;
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
    final watch = Stopwatch()..start();
    final bytes = await _ref.read(apiProvider).speech(text: text.trim(), voice: s.voiceName, speed: s.voiceSpeed, tier: s.tier.name);
    _learn(local: false, chars: text.length, took: watch.elapsed);
    await dir.create(recursive: true);
    final tmp = File('${file.path}.part');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(file.path);
    unawaited(_prune(dir));
    return file;
  }

  /// At most this much audio is kept (the voice on the phone saves
  /// uncompressed WAV, about 3 MB a minute).
  static const keepBytes = 80 * 1000 * 1000;

  /// Keeps the newest passages: at most [keep] files and [keepBytes].
  static Future<void> _prune(Directory dir) async {
    try {
      final files = [
        for (final f in dir.listSync().whereType<File>())
          if (f.path.endsWith('.mp3') || f.path.endsWith('.wav')) (f, f.statSync()),
      ]..sort((a, b) => b.$2.modified.compareTo(a.$2.modified));
      var bytes = 0;
      for (final (i, (file, stat)) in files.indexed) {
        bytes += stat.size;
        if (i >= keep || bytes > keepBytes) file.deleteSync();
      }
    } catch (_) {}
  }

  Future<void> dispose() async {
    _turn++;
    waiting.dispose();
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

int _words(String s) => s.trim().isEmpty ? 0 : s.trim().split(RegExp(r'\s+')).length;

/// A passage in parts the voice on the phone can start on quickly: its
/// sentences, with short ones joined to a neighbour and long ones split at a
/// comma, semicolon or colon (about 40 words at most).
List<String> speechParts(String text) {
  final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (clean.isEmpty) return const [];
  final sentences = [
    for (final m in RegExp(r'[^.!?…]+(?:[.!?…]+["”’)\]]*|$)').allMatches(clean))
      if (m.group(0)!.trim().isNotEmpty) m.group(0)!.trim(),
  ];
  const most = 40;
  final pieces = <String>[];
  for (final sentence in sentences) {
    if (_words(sentence) <= most) {
      pieces.add(sentence);
      continue;
    }
    var part = '';
    for (final clause in sentence.split(RegExp(r'(?<=[,;:])\s+'))) {
      if (part.isNotEmpty && _words(part) + _words(clause) > most) {
        pieces.add(part);
        part = '';
      }
      part = part.isEmpty ? clause : '$part $clause';
    }
    if (part.isNotEmpty) pieces.add(part);
  }
  final parts = <String>[];
  for (final p in pieces) {
    if (parts.isNotEmpty && (_words(parts.last) < 6 || _words(p) < 4) && _words(parts.last) + _words(p) <= most) {
      parts[parts.length - 1] = '${parts.last} $p';
    } else {
      parts.add(p);
    }
  }
  return parts;
}
