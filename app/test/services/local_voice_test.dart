import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:book_reel/data/json_store.dart';
import 'package:book_reel/data/store_provider.dart';
import 'package:book_reel/services/local_voice.dart';
import 'package:book_reel/services/on_device_ai.dart' show LocalCancel;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Stands in for the download (no network in tests).
class FakeInstaller implements LocalVoiceInstaller {
  FakeInstaller({this.installed = false});
  bool installed;
  Object? failWith;
  final steps = <String>[];
  Completer<void>? gate;

  @override
  Future<bool> isInstalled(Directory dir) async => installed;

  @override
  Future<void> install(Directory dir,
      {required void Function(int percent) onProgress, required VoidCallback onUnpacking, required LocalCancel cancel}) async {
    for (final p in [10, 55, 100]) {
      if (cancel.cancelled) return;
      onProgress(p);
      steps.add('$p%');
      await gate?.future;
    }
    if (failWith != null) throw failWith!;
    onUnpacking();
    steps.add('unpacking');
    installed = true;
  }
}

class FakeEngine implements LocalSpeechEngine {
  bool closed = false;
  @override
  Future<void> synthesize({required String text, required int speaker, required double speed, required String path}) async {}
  @override
  Future<void> close() async => closed = true;
}

/// A tiny model archive laid out like the real one.
List<int> fakeArchive() {
  final tar = Archive();
  void add(String name, String content) => tar.addFile(ArchiveFile.string('${LocalVoiceModel.id}/$name', content));
  add('model.int8.onnx', 'onnx');
  add('voices.bin', 'voices');
  add('tokens.txt', 'tokens');
  add('espeak-ng-data/phontab', 'phontab');
  add('espeak-ng-data/en_dict', 'english');
  add('espeak-ng-data/fr_dict', 'french');
  add('espeak-ng-data/voices/default', 'voice');
  return BZip2Encoder().encodeBytes(TarEncoder().encodeBytes(tar));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late JsonStore store;
  late ProviderContainer c;
  late FakeInstaller installer;
  late FakeEngine engine;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('local_voice');
    store = await JsonStore.open(Directory('${dir.path}/store'));
    installer = FakeInstaller();
    engine = FakeEngine();
    LocalVoiceController.installer = installer;
    LocalVoiceController.root = () async => dir;
    LocalSpeech.factory = (_) => engine;
    c = ProviderContainer(overrides: [storeProvider.overrideWithValue(store)]);
  });

  tearDown(() async {
    c.dispose();
    await store.flush();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 10));

  test('download: progress, then getting it ready, then ready; removing it lets the engine go', () async {
    c.read(localVoiceProvider);
    await settle();
    expect(c.read(localVoiceProvider).phase, LocalVoicePhase.absent);
    final seen = <(LocalVoicePhase, int)>[];
    c.listen(localVoiceProvider, (_, s) => seen.add((s.phase, s.progress)), fireImmediately: false);
    await c.read(localVoiceProvider.notifier).download();
    expect(seen, [
      (LocalVoicePhase.downloading, 0),
      (LocalVoicePhase.downloading, 10),
      (LocalVoicePhase.downloading, 55),
      (LocalVoicePhase.downloading, 100),
      (LocalVoicePhase.unpacking, 100),
      (LocalVoicePhase.ready, 0),
    ]);
    expect(c.read(localVoiceProvider).ready, isTrue);
    c.read(localSpeechProvider); // the engine exists once something spoke
    await c.read(localVoiceProvider.notifier).remove();
    expect(c.read(localVoiceProvider).phase, LocalVoicePhase.absent);
    expect(engine.closed, isTrue);
  });

  test('a voice already on the phone is ready at once; a cancelled download leaves nothing; a failed one says why', () async {
    installer.installed = true;
    c.read(localVoiceProvider);
    await settle();
    expect(c.read(localVoiceProvider).ready, isTrue);

    installer.installed = false;
    final again = ProviderContainer(overrides: [storeProvider.overrideWithValue(store)]);
    addTearDown(again.dispose);
    again.read(localVoiceProvider);
    await settle();
    installer.gate = Completer<void>();
    final going = again.read(localVoiceProvider.notifier).download();
    await settle();
    again.read(localVoiceProvider.notifier).cancelDownload();
    installer.gate!.complete();
    await going;
    expect(again.read(localVoiceProvider).phase, LocalVoicePhase.absent);

    installer.gate = null;
    installer.failWith = const SocketException('connection reset');
    await again.read(localVoiceProvider.notifier).download();
    expect(again.read(localVoiceProvider).phase, LocalVoicePhase.failed);
    expect(again.read(localVoiceProvider).message, contains('connection reset'));
  });

  test('the real installer: resumes a cut download, unpacks off the main thread, keeps English only', () async {
    final archive = fakeArchive();
    final requests = <String?>[];
    final client = MockClient.streaming((req, _) async {
      requests.add(req.headers['range']);
      final from = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(req.headers['range'] ?? 'bytes=0-')!.group(1)!);
      return http.StreamedResponse(Stream.value(archive.sublist(from)), from > 0 ? 206 : 200);
    });
    final model = Directory('${dir.path}/voices/${LocalVoiceModel.id}');
    // Half of it came down before the connection dropped.
    await model.parent.create(recursive: true);
    File('${model.parent.path}/${LocalVoiceModel.id}.tar.bz2.part').writeAsBytesSync(archive.sublist(0, archive.length ~/ 2));
    final real = HttpVoiceInstaller(client, archive.length);
    final progress = <int>[];
    var unpacking = false;
    await real.install(model, onProgress: progress.add, onUnpacking: () => unpacking = true, cancel: LocalCancel());
    expect(requests, ['bytes=${archive.length ~/ 2}-'], reason: 'only the rest is fetched');
    expect(progress.last, 100);
    expect(unpacking, isTrue);
    expect(await real.isInstalled(model), isTrue);
    expect(File('${model.path}/espeak-ng-data/en_dict').existsSync(), isTrue);
    expect(File('${model.path}/espeak-ng-data/fr_dict').existsSync(), isFalse, reason: 'other languages are dropped');
    expect(File('${model.path}/espeak-ng-data/voices/default').existsSync(), isTrue, reason: 'only dictionaries go');
    expect(File('${model.parent.path}/${LocalVoiceModel.id}.tar.bz2').existsSync(), isFalse, reason: 'the archive is deleted');
  });

  test('voices map to the model’s speakers', () {
    expect([for (final v in ['af_heart', 'am_michael', 'bf_emma', 'bm_george', 'unknown']) localSpeakerFor(v)], [1, 6, 7, 9, 1]);
  });
}
