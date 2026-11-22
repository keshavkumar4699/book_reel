import 'dart:async';
import 'dart:io';

import 'package:book_reel/services/local_voice.dart';
import 'package:book_reel/services/on_device_ai.dart' show LocalCancel;
import 'package:book_reel/services/read_aloud.dart';
import 'package:flutter/foundation.dart';

/// A read-aloud player that plays nothing: it records what it was given,
/// and [finish] or [fail] say how the file ended.
class FakeSpeechPlayer implements SpeechPlayer {
  final played = <String>[];
  final _done = StreamController<void>.broadcast();
  final _failed = StreamController<void>.broadcast();
  bool stopped = false;

  void finish() => _done.add(null);

  /// The file playing turned out to be unplayable.
  void fail() => _failed.add(null);

  @override
  Stream<void> get completed => _done.stream;
  @override
  Stream<void> get failed => _failed.stream;
  @override
  Future<void> playFile(String path) async => played.add(path);
  @override
  Future<void> stop() async => stopped = true;
  @override
  Future<void> dispose() async {
    await _done.close();
    await _failed.close();
  }
}

/// The voice on the phone, without the model: it "speaks" into a small file.
class FakeLocalEngine implements LocalSpeechEngine {
  final spoken = <String>[];
  Object? failWith;

  @override
  Future<void> synthesize({required String text, required int speaker, required double speed, required String path}) async {
    if (failWith != null) throw failWith!;
    spoken.add(text);
    File(path).writeAsStringSync('RIFF $speaker $speed $text');
  }

  @override
  Future<void> close() async {}
}

/// A voice on the phone that takes its time: nothing is made until [gate] opens.
class GatedLocalEngine extends FakeLocalEngine {
  final gate = Completer<void>();

  @override
  Future<void> synthesize({required String text, required int speaker, required double speed, required String path}) async {
    await gate.future;
    return super.synthesize(text: text, speaker: speaker, speed: speed, path: path);
  }
}

class InstalledVoice implements LocalVoiceInstaller {
  @override
  Future<bool> isInstalled(Directory dir) async => true;
  @override
  Future<void> install(Directory dir,
      {required void Function(int percent) onProgress, required VoidCallback onUnpacking, required LocalCancel cancel}) async {}
}
