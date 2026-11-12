import 'dart:async';
import 'dart:io';

import 'package:book_reel/data/api_client.dart';
import 'package:book_reel/data/json_store.dart';
import 'package:book_reel/data/settings.dart';
import 'package:book_reel/data/settings_provider.dart';
import 'package:book_reel/data/store_provider.dart';
import 'package:book_reel/services/read_aloud.dart';
import 'package:book_reel/services/tts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../data/fake_server.dart';

class FakeSpeechPlayer implements SpeechPlayer {
  final played = <String>[];
  final _done = StreamController<void>.broadcast();
  bool stopped = false;

  void finish() => _done.add(null);

  @override
  Stream<void> get completed => _done.stream;
  @override
  Future<void> playFile(String path) async => played.add(path);
  @override
  Future<void> stop() async => stopped = true;
  @override
  Future<void> dispose() async => _done.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late FakeServer server;
  late FakeSpeechPlayer player;
  late ProviderContainer c;
  late JsonStore store;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('read_aloud');
    server = FakeServer();
    player = FakeSpeechPlayer();
    ReadAloud.playerFactory = () => player;
    ReadAloud.cacheRoot = () async => dir;
    store = await JsonStore.open(Directory('${dir.path}/store'));
    c = ProviderContainer(overrides: [
      storeProvider.overrideWithValue(store),
      apiProvider.overrideWithValue(BookReelApi(baseUrl: 'http://fake', deviceId: 'dev1', httpClient: server.client)),
    ]);
  });

  tearDown(() async {
    c.dispose();
    await store.flush();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('the natural voice plays each passage, fetches the next one early, and keeps both on the phone', () async {
    c.read(settingsProvider.notifier).update((s) => s.copyWith(voiceName: 'bf_emma', voiceSpeed: 1.1));
    final read = c.read(readAloudProvider);
    var done = 0;
    await read.speak('Down the rabbit hole.', next: 'Curiouser and curiouser!', onDone: () => done++);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(server.speechRequests.map((r) => r['text']), ['Down the rabbit hole.', 'Curiouser and curiouser!']);
    expect(server.speechRequests.first, containsPair('voice', 'bf_emma'));
    expect(server.speechRequests.first, containsPair('speed', 1.1));
    expect(player.played, hasLength(1));
    expect(File(player.played.single).readAsStringSync(), 'ID3 mp3 bf_emma Down the rabbit hole.');
    player.finish();
    await Future<void>.delayed(Duration.zero);
    expect(done, 1);

    // The next reel was fetched while this one played: it starts at once.
    await read.speak('Curiouser and curiouser!', onDone: () {});
    expect(server.speechRequests, hasLength(2));
    expect(player.played, hasLength(2));
    // Hearing a passage again never asks the server.
    await read.speak('Down the rabbit hole.', onDone: () {});
    expect(server.speechRequests, hasLength(2));
    expect(read.naturalActive, isTrue);
  });

  test('without a voice on the server, the phone reads and the natural voice rests for a while', () async {
    server.speechStatus = 503;
    final read = c.read(readAloudProvider);
    await read.speak('Hello there.', onDone: () {});
    expect(player.played, isEmpty);
    expect(read.naturalActive, isFalse);
    // Choosing the phone voice never calls the server.
    server.speechStatus = 200;
    c.read(settingsProvider.notifier).update((s) => s.copyWith(naturalVoice: false));
    await read.speak('Hello again.', onDone: () {});
    expect(server.speechRequests, isEmpty);
  });

  test('the phone voice is the most natural one installed', () {
    final voices = [
      {'name': 'en-us-x-sfg-local', 'locale': 'en-US', 'quality': 'normal', 'network_required': '0', 'features': ''},
      {'name': 'en-in-x-ene-local', 'locale': 'en-IN', 'quality': 'very high', 'network_required': '0', 'features': ''},
      {'name': 'en-in-x-net-network', 'locale': 'en-IN', 'quality': 'very high', 'network_required': '1', 'features': ''},
      {'name': 'en-gb-x-gbd-local', 'locale': 'en-GB', 'quality': 'very high', 'network_required': '0', 'features': 'notInstalled'},
      {'name': 'hi-in-x-hia-local', 'locale': 'hi-IN', 'quality': 'very high', 'network_required': '0', 'features': ''},
    ];
    expect(bestPhoneVoice(voices, language: 'en', country: 'IN')!['name'], 'en-in-x-ene-local');
    expect(bestPhoneVoice(voices, language: 'en', country: 'US')!['name'], 'en-in-x-ene-local', reason: 'quality first');
    expect(bestPhoneVoice(voices, language: 'fr'), isNull);
  });

  test('voice settings are kept', () {
    const s = AppSettings(naturalVoice: false, voiceName: 'bm_george', voiceSpeed: 1.2);
    final back = AppSettings.fromJson(s.toJson());
    expect((back.naturalVoice, back.voiceName, back.voiceSpeed), (false, 'bm_george', 1.2));
    expect(AppSettings.fromJson(const {'voiceSpeed': 5}).voiceSpeed, 1.4);
    expect(const AppSettings().naturalVoice, isTrue);
    expect(speechVoices.map((v) => v.id), ['af_heart', 'am_michael', 'bf_emma', 'bm_george']);
  });
}
