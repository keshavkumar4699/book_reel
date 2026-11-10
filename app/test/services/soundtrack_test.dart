import 'dart:io';

import 'package:book_reel/core/models/reel_card.dart';
import 'package:book_reel/data/api_client.dart';
import 'package:book_reel/data/json_store.dart';
import 'package:book_reel/data/settings.dart';
import 'package:book_reel/data/settings_provider.dart';
import 'package:book_reel/data/store_provider.dart';
import 'package:book_reel/services/soundtrack.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../data/fake_server.dart';

class FakeEngine implements AudioEngine {
  final List<String> played = [];
  final List<double> volumes = [];
  bool stopped = false;
  @override
  Future<void> crossfadeTo(String url, double volume) async {
    played.add(url);
    volumes.add(volume);
  }

  @override
  Future<void> setVolume(double volume) async => volumes.add(volume);

  @override
  Future<void> stop() async => stopped = true;
}

Map<String, dynamic> track(String id, List<String> moods, int energy) => {
      'id': id,
      'title': id,
      'artist': 'NCS Artist',
      'url': 'https://cdn.example.com/$id.mp3',
      'moods': moods,
      'energy': energy,
      'license': 'test',
      'attribution': 'NCS Artist – $id',
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late FakeEngine engine;
  late FakeServer server;
  late JsonStore store;

  Future<ProviderContainer> container(Tier tier) async {
    dir = await Directory.systemTemp.createTemp('soundtrack');
    store = await JsonStore.open(dir);
    final c = ProviderContainer(overrides: [
      storeProvider.overrideWithValue(store),
      apiProvider.overrideWithValue(BookReelApi(baseUrl: 'http://fake', deviceId: 'd1', httpClient: server.client)),
    ]);
    c.read(settingsProvider.notifier).update((s) => s.copyWith(tier: tier, musicVolume: 0.5));
    return c;
  }

  setUp(() {
    engine = FakeEngine();
    SoundtrackNotifier.engineFactory = () => engine;
    server = FakeServer()
      ..musicTracks = [track('calm1', ['calm'], 1), track('tense1', ['tense'], 4)];
  });

  tearDown(() async {
    await store.flush(); // pending settings writes
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('paid users get music that follows the AI mood of each card', () async {
    final c = await container(Tier.pro);
    final st = c.read(soundtrackProvider.notifier);
    await st.loadCatalog();
    expect(c.read(soundtrackProvider).tracks, hasLength(2));

    final t0 = DateTime(2026, 1, 1, 9);
    await st.onCard('calm', 1, now: t0);
    expect(engine.played, ['https://cdn.example.com/calm1.mp3']);
    expect(engine.volumes.last, 0.5);
    await st.onCard('tense', 4, now: t0.add(const Duration(seconds: 40)));
    await st.onCard('tense', 4, now: t0.add(const Duration(seconds: 45)));
    expect(engine.played.last, 'https://cdn.example.com/tense1.mp3');
    expect(c.read(soundtrackProvider).playing!.attribution, 'NCS Artist – tense1');

    await st.duck(true);
    expect(engine.volumes.last, closeTo(0.15, 1e-9));
    await st.duck(false);
    await st.stop();
    expect(engine.stopped, isTrue);
    expect(c.read(soundtrackProvider).playing, isNull);
    c.dispose();
  });

  test('chapters with AI music cues follow the plan picked by the AI supervisor', () async {
    server.planPicks = {'calm': 'calm1', 'tense': 'tense1'};
    final c = await container(Tier.pro);
    final st = c.read(soundtrackProvider.notifier);
    await st.loadCatalog();
    const cues = [MusicCue(atCard: 0, mood: 'calm', energy: 1), MusicCue(atCard: 10, mood: 'tense', energy: 4)];
    final t0 = DateTime(2026, 1, 1, 9);
    await st.onPosition(chapterKey: 'b:0', cues: cues, cardIndex: 0, chapterStart: true, now: t0);
    expect(engine.played, ['https://cdn.example.com/calm1.mp3']);
    await st.onPosition(chapterKey: 'b:0', cues: cues, cardIndex: 4, now: t0.add(const Duration(seconds: 20)));
    expect(engine.played, hasLength(1), reason: 'same cue, same track');
    await st.onPosition(chapterKey: 'b:0', cues: cues, cardIndex: 10, now: t0.add(const Duration(seconds: 60)));
    expect(engine.played.last, 'https://cdn.example.com/tense1.mp3');
    expect(c.read(soundtrackProvider).mood, 'tense');
    expect(server.musicPlanRequests, 1, reason: 'the plan is fetched once per chapter');
    c.dispose();
  });

  test('without the plan service, cues are matched to tracks on the device', () async {
    server.failMusicPlan = true;
    final c = await container(Tier.plus);
    final st = c.read(soundtrackProvider.notifier);
    await st.loadCatalog();
    await st.onPosition(
      chapterKey: 'b:1',
      cues: const [MusicCue(atCard: 0, mood: 'tense', energy: 4)],
      cardIndex: 2,
      chapterStart: true,
    );
    expect(engine.played, ['https://cdn.example.com/tense1.mp3']);
    c.dispose();
  });

  test('free users get no music and never call the catalog', () async {
    final c = await container(Tier.free);
    final st = c.read(soundtrackProvider.notifier);
    await st.loadCatalog();
    await st.onCard('calm', 1);
    expect(engine.played, isEmpty);
    expect(server.requests, 0);
    c.dispose();
  });

  test('turning the soundtrack off in settings silences it', () async {
    final c = await container(Tier.plus);
    c.read(settingsProvider.notifier).update((s) => s.copyWith(soundtrack: false));
    final st = c.read(soundtrackProvider.notifier);
    await st.loadCatalog();
    await st.onCard('calm', 1);
    expect(engine.played, isEmpty);
    c.dispose();
  });

  test('an empty catalog explains why there is no music', () async {
    server.musicTracks = [];
    final c = await container(Tier.scholar);
    await c.read(soundtrackProvider.notifier).loadCatalog();
    expect(c.read(soundtrackProvider).message, contains('No licensed tracks'));
    c.dispose();
  });
}
