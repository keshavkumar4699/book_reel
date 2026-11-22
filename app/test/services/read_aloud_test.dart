import 'dart:async';
import 'dart:io';

import 'package:book_reel/data/api_client.dart';
import 'package:book_reel/data/json_store.dart';
import 'package:book_reel/data/settings.dart';
import 'package:book_reel/data/settings_provider.dart';
import 'package:book_reel/data/store_provider.dart';
import 'package:book_reel/services/local_voice.dart';
import 'package:book_reel/services/read_aloud.dart';
import 'package:book_reel/services/tts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../data/fake_server.dart';
import '../fake_voice.dart';

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
    await read.speak('Down the rabbit hole.', ahead: ['Curiouser and curiouser!'], onDone: () => done++);
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

  test('a passage is spoken in parts: sentences, short ones joined, long ones split at a comma', () {
    expect(speechParts('  '), isEmpty);
    // Whole sentences, one part each.
    const a = 'Alice was beginning to get very tired of sitting by her sister on the bank.';
    const b = 'Once or twice she had peeped into the book her sister was reading.';
    const c2 = 'So she was considering in her own mind what to do.';
    expect(speechParts('$a $b $c2'), [a, b, c2]);
    // Short ones join a neighbour: a 4-word opening the next sentence, a fragment the one before.
    expect(speechParts('Down the rabbit hole. $a “Oh dear!” she said.'), ['Down the rabbit hole. $a “Oh dear!” she said.']);
    final long = List.generate(30, (i) => 'word$i').join(' ');
    final parts = speechParts('$long, and then $long; at last the end.');
    expect(parts.length, greaterThan(1));
    expect(parts.every((p) => p.split(' ').length <= 40), isTrue);
    expect(parts.join(' '), '$long, and then $long; at last the end.');
  });

  test('the voice on the phone reads part by part, makes the next part as one plays, and keeps them', () async {
    final engine = FakeLocalEngine();
    LocalVoiceController.installer = InstalledVoice();
    LocalVoiceController.root = () async => dir;
    LocalSpeech.factory = (_) => engine;
    c.read(localVoiceProvider);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    c.read(settingsProvider.notifier).update((s) => s.copyWith(voiceName: 'bm_george', voiceSpeed: 1.1));
    final read = c.read(readAloudProvider);
    expect(read.localActive, isTrue);
    var done = 0;
    const first = 'Alice was beginning to get very tired of sitting by her sister on the bank.';
    const second = 'Once or twice she had peeped into the book her sister was reading.';
    await read.speak('$first $second', ahead: ['So she was considering in her own mind. And more.'], onDone: () => done++);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(player.played, hasLength(1), reason: 'the first part plays as soon as it is ready');
    expect(File(player.played.single).readAsStringSync(), 'RIFF 9 1.1 $first', reason: 'George, at the chosen speed');
    expect(engine.spoken, [first, second, 'So she was considering in her own mind. And more.'],
        reason: 'the second part is made while the first plays, then the next reel');
    player.finish();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(player.played, hasLength(2));
    expect(done, 0);
    expect(engine.spoken.last, 'So she was considering in her own mind. And more.', reason: 'the next reel’s first part, made early');
    player.finish();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(done, 1);
    expect(server.speechRequests, isEmpty, reason: 'nothing leaves the phone');
    // Heard again: from the phone's cache, nothing made again.
    final made = engine.spoken.length;
    await read.speak('$first $second', onDone: () {});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(engine.spoken, hasLength(made));
  });

  test('while a reel plays, the next two and the one before are made ready, nearest first', () async {
    final engine = FakeLocalEngine();
    LocalVoiceController.installer = InstalledVoice();
    LocalVoiceController.root = () async => dir;
    LocalSpeech.factory = (_) => engine;
    c.read(localVoiceProvider);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final read = c.read(readAloudProvider);
    const now = 'This is the reel on screen now, read aloud.';
    const next = 'The next reel comes after this one.';
    const after = 'And the one after that, two along.';
    const before = 'The reel before the one on screen.';
    await read.speak(now, ahead: [next, after], behind: before, onDone: () {});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(engine.spoken, [now, next, after, before]);
    // Moving on, or back, plays at once: nothing is made again.
    await read.speak(next, ahead: [after], behind: now, onDone: () {});
    await read.speak(before, ahead: [now, next], onDone: () {});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(engine.spoken, hasLength(4));
    expect(player.played, hasLength(3));
  });

  test('a reel that takes a moment to make says so, with the time it should take', () async {
    final engine = GatedLocalEngine();
    LocalVoiceController.installer = InstalledVoice();
    LocalVoiceController.root = () async => dir;
    LocalSpeech.factory = (_) => engine;
    final wasAfter = ReadAloud.showWaitAfter;
    ReadAloud.showWaitAfter = const Duration(milliseconds: 5);
    addTearDown(() => ReadAloud.showWaitAfter = wasAfter);
    c.read(localVoiceProvider);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final read = c.read(readAloudProvider);
    const text = 'Alice was beginning to get very tired of sitting by her sister on the bank.';
    final speaking = read.speak(text, onDone: () {});
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(read.waiting.value, isNotNull);
    expect(read.waiting.value!.chars, text.length);
    expect(read.waiting.value!.expected, greaterThan(const Duration(milliseconds: 500)));
    expect(player.played, isEmpty);
    engine.gate.complete();
    await speaking;
    expect(read.waiting.value, isNull, reason: 'gone once the audio starts');
    expect(player.played, hasLength(1));
    // Stopping clears it too.
    final again = GatedLocalEngine();
    LocalSpeech.factory = (_) => again;
    c.invalidate(localSpeechProvider);
    unawaited(read.speak('Once or twice she had peeped into the book her sister was reading.', onDone: () {}));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(read.waiting.value, isNotNull);
    await read.stop();
    expect(read.waiting.value, isNull);
    again.gate.complete();
  });

  test('a voice that won’t load on this phone says so, and the server voice reads instead', () async {
    final engine = FakeLocalEngine()..failWith = const VoiceLoadFailure('the model did not load');
    LocalVoiceController.installer = InstalledVoice();
    LocalVoiceController.root = () async => dir;
    LocalSpeech.factory = (_) => engine;
    c.read(localVoiceProvider);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final read = c.read(readAloudProvider);
    await read.speak('Down the rabbit hole.', onDone: () {});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(c.read(localVoiceProvider).phase, LocalVoicePhase.failed);
    expect(c.read(localVoiceProvider).message, contains('did not load'));
    expect(server.speechRequests.single['text'], 'Down the rabbit hole.');
    expect(read.localActive, isFalse);
  });

  test('audio that won’t play ends the passage: the file is dropped, that voice rests, the listener is told', () async {
    final engine = FakeLocalEngine();
    LocalVoiceController.installer = InstalledVoice();
    LocalVoiceController.root = () async => dir;
    LocalSpeech.factory = (_) => engine;
    c.read(localVoiceProvider);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final read = c.read(readAloudProvider);
    final stops = <SpeechStopped>[];
    var done = 0;
    await read.speak('Down the rabbit hole. Curiouser and curiouser!', onDone: () => done++, onStopped: stops.add);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final file = File(player.played.single);
    expect(file.existsSync(), isTrue);
    player.fail();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(stops, [SpeechStopped.failed]);
    expect(file.existsSync(), isFalse, reason: 'made again next time, not played broken again');
    expect(read.localActive, isFalse, reason: 'the voice on the phone rests a while');
    player.finish(); // nothing else was waiting on it
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(done, 0);
    expect(player.played, hasLength(1));
  });

  test('a word said over a passage stops it and tells its listener; stop and the next passage don’t', () async {
    final read = c.read(readAloudProvider);
    final stops = <String>[];
    await read.speak('Down the rabbit hole.', onDone: () {}, onStopped: (why) => stops.add('first ${why.name}'));
    await read.speak('Curiouser and curiouser!', onDone: () {}, onStopped: (why) => stops.add('second ${why.name}'));
    await read.stop();
    expect(stops, isEmpty, reason: 'moving on, or stopping, is the listener’s own doing');
    await read.speak('Down the rabbit hole.', onDone: () {}, onStopped: (why) => stops.add('third ${why.name}'));
    await read.sayWord('rabbit');
    expect(stops, ['third interrupted']);
    expect(player.stopped, isTrue);
    await read.sample('A voice’s sample.');
    expect(stops, ['third interrupted'], reason: 'told once');
  });

  test('the voice on the phone never leaves a half-made file to be taken for a finished one', () async {
    final engine = FakeLocalEngine();
    LocalVoiceController.installer = InstalledVoice();
    LocalVoiceController.root = () async => dir;
    LocalSpeech.factory = (_) => engine;
    c.read(localVoiceProvider);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final read = c.read(readAloudProvider);
    await read.speak('Down the rabbit hole.', onDone: () {});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final names = Directory('${dir.path}/speech').listSync().map((f) => f.path.split('/').last).toList();
    expect(names.where((n) => n.endsWith('.wav')), hasLength(1));
    expect(names.where((n) => n.endsWith('.part')), isEmpty);
  });
}
