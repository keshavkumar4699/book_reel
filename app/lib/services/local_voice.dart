import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'on_device_ai.dart' show LocalCancel, formatBytes;
import '../l10n/l10n.dart';

/// The natural voice on the phone: Kokoro (82M parameters, Apache 2.0), run
/// by sherpa-onnx. Downloaded once, then free, unlimited and offline; the
/// way to hear a voice close to a person reading without a Cloro server.
class LocalVoiceModel {
  const LocalVoiceModel._();

  static const id = 'kokoro-int8-en-v0_19';
  static const url = 'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/$id.tar.bz2';
  static const downloadBytes = 103248205;

  /// On the phone once unpacked (other languages' pronunciation data removed).
  static const installedBytes = 141 * 1000 * 1000;

  /// What has to be there for the voice to load.
  static const requiredFiles = ['model.int8.onnx', 'voices.bin', 'tokens.txt', 'espeak-ng-data/phontab', 'espeak-ng-data/en_dict'];
}

/// The voices (by the ids the server's voices use) as speakers of the
/// on-device model: 1 af_bella, 6 am_michael, 7 bf_emma, 9 bm_george.
const localSpeakers = <String, int>{'af_heart': 1, 'am_michael': 6, 'bf_emma': 7, 'bm_george': 9};

int localSpeakerFor(String voice) => localSpeakers[voice] ?? 1;

enum LocalVoicePhase { checking, absent, downloading, unpacking, ready, failed }

@immutable
class LocalVoiceState {
  const LocalVoiceState({this.phase = LocalVoicePhase.checking, this.progress = 0, this.message});

  final LocalVoicePhase phase;

  /// Download progress, 0–100.
  final int progress;
  final String? message;

  bool get ready => phase == LocalVoicePhase.ready;
  bool get busy => phase == LocalVoicePhase.downloading || phase == LocalVoicePhase.unpacking;
}

/// Downloads and unpacks the model (the seam tests replace).
abstract class LocalVoiceInstaller {
  Future<bool> isInstalled(Directory dir);

  /// Fetches the model into [dir]; [onProgress] gets 0–100 while it
  /// downloads, then [onUnpacking] is called once.
  Future<void> install(Directory dir,
      {required void Function(int percent) onProgress, required VoidCallback onUnpacking, required LocalCancel cancel});
}

class HttpVoiceInstaller implements LocalVoiceInstaller {
  HttpVoiceInstaller([this._client, this.expectedBytes = LocalVoiceModel.downloadBytes]);
  final http.Client? _client;

  /// The archive's size, to show progress and to know it all arrived.
  final int expectedBytes;

  @override
  Future<bool> isInstalled(Directory dir) async {
    for (final f in LocalVoiceModel.requiredFiles) {
      if (!await File('${dir.path}/$f').exists()) return false;
    }
    return true;
  }

  @override
  Future<void> install(Directory dir,
      {required void Function(int percent) onProgress, required VoidCallback onUnpacking, required LocalCancel cancel}) async {
    final parent = dir.parent;
    await parent.create(recursive: true);
    final archive = File('${parent.path}/${LocalVoiceModel.id}.tar.bz2');
    final part = File('${archive.path}.part');
    final client = _client ?? http.Client();
    try {
      // Carries on from where a cut download stopped.
      var have = await part.exists() ? await part.length() : 0;
      if (have < expectedBytes && !await archive.exists()) {
        final req = http.Request('GET', Uri.parse(LocalVoiceModel.url));
        if (have > 0) req.headers['range'] = 'bytes=$have-';
        cancel.onCancel = client.close;
        final res = await client.send(req).timeout(const Duration(seconds: 30));
        if (res.statusCode != 200 && res.statusCode != 206) throw HttpException('download failed (${res.statusCode})');
        if (res.statusCode == 200) have = 0; // the server sent it all again
        final sink = part.openWrite(mode: have > 0 ? FileMode.append : FileMode.write);
        try {
          var last = -1;
          await for (final chunk in res.stream) {
            if (cancel.cancelled) break;
            sink.add(chunk);
            have += chunk.length;
            final p = (have * 100 ~/ expectedBytes).clamp(0, 100);
            if (p != last) onProgress(last = p);
          }
        } finally {
          await sink.close();
        }
        if (cancel.cancelled) return;
        if (have < expectedBytes) throw const HttpException('the download stopped early');
        await part.rename(archive.path);
      }
      if (cancel.cancelled) return;
      onUnpacking();
      final tmp = Directory('${dir.path}.unpacking');
      if (await tmp.exists()) await tmp.delete(recursive: true);
      // Decompressing 100 MB takes a while: away from the screen's thread.
      await Isolate.run(_unpackJob(archive.path, tmp.path));
      if (await dir.exists()) await dir.delete(recursive: true);
      await Directory('${tmp.path}/${LocalVoiceModel.id}').rename(dir.path);
      await tmp.delete(recursive: true);
      await archive.delete();
      if (!await isInstalled(dir)) throw const FileSystemException('the voice files are incomplete');
    } finally {
      cancel.onCancel = null;
      if (_client == null) client.close();
    }
  }
}

/// The unpacking as a job for another isolate. Made here, not inline: a
/// closure inside an async method would carry the method's state along,
/// the HTTP client included, which can't be sent.
Future<void> Function() _unpackJob(String archive, String outDir) => () => unpackVoice(archive, outDir);

/// Unpacks the model archive at [archive] into [outDir] (streaming, so memory
/// stays small), then drops the pronunciation data of languages other than
/// English (about 18 MB).
Future<void> unpackVoice(String archive, String outDir) async {
  await extractFileToDisk(archive, outDir, verify: true);
  final data = Directory('$outDir/${LocalVoiceModel.id}/espeak-ng-data');
  if (!data.existsSync()) return;
  for (final e in data.listSync()) {
    final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
    if (e is File && name.endsWith('_dict') && name != 'en_dict') e.deleteSync();
  }
}

/// Downloads, removes and reports the on-device voice.
class LocalVoiceController extends Notifier<LocalVoiceState> {
  /// Tests replace these.
  static LocalVoiceInstaller installer = HttpVoiceInstaller();
  static Future<Directory> Function() root = getApplicationSupportDirectory;

  LocalCancel? _download;
  Directory? _dir;

  @override
  LocalVoiceState build() {
    ref.onDispose(() => _download?.cancel());
    unawaited(_check());
    return const LocalVoiceState();
  }

  /// Where the model lives once unpacked.
  Future<Directory> modelDir() async => _dir ??= Directory('${(await root()).path}/voices/${LocalVoiceModel.id}');

  Future<void> _check() async {
    try {
      final ok = await installer.isInstalled(await modelDir());
      if (ref.mounted && state.phase == LocalVoicePhase.checking) {
        state = LocalVoiceState(phase: ok ? LocalVoicePhase.ready : LocalVoicePhase.absent);
      }
    } catch (_) {
      if (ref.mounted) state = const LocalVoiceState(phase: LocalVoicePhase.absent);
    }
  }

  /// Downloads (about 100 MB) and unpacks the voice.
  Future<void> download() async {
    if (state.busy || state.ready) return;
    final cancel = _download = LocalCancel();
    state = const LocalVoiceState(phase: LocalVoicePhase.downloading);
    try {
      await installer.install(
        await modelDir(),
        cancel: cancel,
        onProgress: (p) {
          if (!cancel.cancelled && ref.mounted && state.phase == LocalVoicePhase.downloading) {
            state = LocalVoiceState(phase: LocalVoicePhase.downloading, progress: p);
          }
        },
        onUnpacking: () {
          if (ref.mounted) state = const LocalVoiceState(phase: LocalVoicePhase.unpacking, progress: 100);
        },
      );
      if (!ref.mounted) return;
      state = cancel.cancelled ? const LocalVoiceState(phase: LocalVoicePhase.absent) : const LocalVoiceState(phase: LocalVoicePhase.ready);
    } catch (e) {
      if (!ref.mounted) return;
      state = cancel.cancelled
          ? const LocalVoiceState(phase: LocalVoicePhase.absent)
          : LocalVoiceState(phase: LocalVoicePhase.failed, message: tr('The download stopped ({error}). Try again, ideally on Wi-Fi.', {'error': _short(e)}));
    } finally {
      if (identical(_download, cancel)) _download = null;
    }
  }

  void cancelDownload() => _download?.cancel();

  /// The voice failed to load on this phone: say so, and fall back.
  void markBroken(Object error) {
    state = LocalVoiceState(phase: LocalVoicePhase.failed, message: tr('The voice couldn’t start on this phone ({error}).', {'error': _short(error)}));
  }

  /// Deletes the voice (and any half-finished download).
  Future<void> remove() async {
    _download?.cancel();
    await ref.read(localSpeechProvider).close();
    final dir = await modelDir();
    for (final e in [dir, Directory('${dir.path}.unpacking')]) {
      if (await e.exists()) await e.delete(recursive: true);
    }
    for (final f in [File('${dir.parent.path}/${LocalVoiceModel.id}.tar.bz2'), File('${dir.parent.path}/${LocalVoiceModel.id}.tar.bz2.part')]) {
      if (await f.exists()) await f.delete();
    }
    if (ref.mounted) state = const LocalVoiceState(phase: LocalVoicePhase.absent);
  }

  static String _short(Object e) {
    final s = '$e'.replaceFirst(RegExp(r'^\w*(Exception|Error): ?'), '');
    return s.length > 80 ? '${s.substring(0, 80)}…' : s;
  }
}

final localVoiceProvider = NotifierProvider<LocalVoiceController, LocalVoiceState>(LocalVoiceController.new);

/// The download, in words: "103 MB".
String get localVoiceDownloadSize => formatBytes(LocalVoiceModel.downloadBytes);

// ---------------------------------------------------------------- speaking

/// The voice on the phone didn't load (a broken download, too little memory).
class VoiceLoadFailure implements Exception {
  const VoiceLoadFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Turns text into speech on the phone (the seam tests replace).
abstract class LocalSpeechEngine {
  /// Writes [text], spoken by [speaker] at [speed], as a WAV file at [path].
  Future<void> synthesize({required String text, required int speaker, required double speed, required String path});

  /// Lets the model go (it holds a few hundred MB while loaded).
  Future<void> close();
}

/// Kokoro in a worker isolate of its own: loading takes a few seconds and
/// speaking a sentence about one, so neither ever blocks the screen. Requests
/// are spoken in order; the model is let go after a few idle minutes.
class SherpaSpeechEngine implements LocalSpeechEngine {
  SherpaSpeechEngine(this.modelDir);

  final Future<Directory> Function() modelDir;
  static const idle = Duration(minutes: 3);

  Future<SendPort>? _worker;
  Isolate? _isolate;
  ReceivePort? _replies;
  final Map<int, Completer<void>> _waiting = {};
  int _next = 0;
  Timer? _idle;

  Future<SendPort> _start() async {
    final dir = (await modelDir()).path;
    final replies = _replies = ReceivePort();
    final ready = Completer<SendPort>();
    replies.listen((msg) {
      if (msg is SendPort) {
        if (!ready.isCompleted) ready.complete(msg);
      } else if (msg is (int, String?)) {
        final (id, error) = msg;
        final c = _waiting.remove(id);
        if (c == null) return;
        error == null ? c.complete() : c.completeError(StateError(error));
      } else if (msg is String) {
        // The model didn't load.
        if (!ready.isCompleted) ready.completeError(VoiceLoadFailure(msg));
      }
    });
    final threads = Platform.numberOfProcessors >= 6 ? 4 : 2;
    _isolate = await Isolate.spawn(_speechWorker, (replies.sendPort, dir, threads), debugName: 'voice');
    return ready.future;
  }

  @override
  Future<void> synthesize({required String text, required int speaker, required double speed, required String path}) async {
    _idle?.cancel();
    final worker = await (_worker ??= _start().catchError((Object e) {
      _worker = null;
      _shutdown(kill: true);
      throw e;
    }));
    final id = _next++;
    final done = _waiting[id] = Completer<void>();
    worker.send((id, text, speaker, speed, path));
    try {
      await done.future;
    } finally {
      if (_waiting.isEmpty) _idle = Timer(idle, () => unawaited(close()));
    }
  }

  @override
  Future<void> close() async {
    _idle?.cancel();
    final worker = _worker;
    _worker = null;
    if (worker != null) {
      try {
        (await worker).send(null);
      } catch (_) {}
    }
    _shutdown();
  }

  /// Fails what's waiting and stops listening. The worker frees the model
  /// itself when told to close; [kill] is for one that never started.
  void _shutdown({bool kill = false}) {
    for (final c in _waiting.values) {
      if (!c.isCompleted) c.completeError(StateError('the voice was closed'));
    }
    _waiting.clear();
    _replies?.close();
    _replies = null;
    if (kill) _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
  }
}

/// The worker: loads the model, then speaks each request into a WAV file.
void _speechWorker((SendPort, String, int) args) {
  final (reply, dir, threads) = args;
  final sherpa.OfflineTts tts;
  try {
    sherpa.initBindings();
    tts = sherpa.OfflineTts(sherpa.OfflineTtsConfig(
      model: sherpa.OfflineTtsModelConfig(
        kokoro: sherpa.OfflineTtsKokoroModelConfig(
          model: '$dir/model.int8.onnx',
          voices: '$dir/voices.bin',
          tokens: '$dir/tokens.txt',
          dataDir: '$dir/espeak-ng-data',
        ),
        numThreads: threads,
      ),
    ));
    if (tts.ptr.address == 0) throw StateError('the model did not load');
  } catch (e) {
    reply.send('$e');
    return;
  }
  final inbox = ReceivePort();
  reply.send(inbox.sendPort);
  inbox.listen((msg) {
    if (msg == null) {
      tts.free();
      inbox.close();
      return;
    }
    final (id, text, speaker, speed, path) = msg as (int, String, int, double, String);
    try {
      final audio = tts.generate(text: text, sid: speaker, speed: speed);
      if (audio.samples.isEmpty) throw StateError('no audio');
      final tmp = '$path.part';
      if (!sherpa.writeWave(filename: tmp, samples: audio.samples, sampleRate: audio.sampleRate)) throw StateError('could not save the audio');
      File(tmp).renameSync(path);
      reply.send((id, null));
    } catch (e) {
      reply.send((id, '$e'));
    }
  });
}

final localSpeechProvider = Provider<LocalSpeechEngine>((ref) {
  final engine = LocalSpeech.factory(() => ref.read(localVoiceProvider.notifier).modelDir());
  ref.onDispose(() => unawaited(engine.close()));
  return engine;
});

/// How the engine is made (tests replace it).
class LocalSpeech {
  const LocalSpeech._();
  static LocalSpeechEngine Function(Future<Directory> Function() modelDir) factory = SherpaSpeechEngine.new;
}
