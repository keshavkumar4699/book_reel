import 'dart:io';

import 'package:book_reel/data/json_store.dart';
import 'package:book_reel/data/settings.dart';
import 'package:book_reel/data/settings_provider.dart';
import 'package:book_reel/data/store_provider.dart';
import 'package:book_reel/services/scene_sound.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeLoop implements LoopPlayer {
  FakeLoop(this.all) {
    all.add(this);
  }
  final List<FakeLoop> all;
  String? asset;
  double volume = 1;
  bool playing = false;
  bool disposed = false;

  @override
  Future<void> load(String asset) async => this.asset = asset;
  @override
  Future<void> setVolume(double volume) async => this.volume = volume;
  @override
  Future<void> play() async => playing = true;
  @override
  Future<void> pause() async => playing = false;
  @override
  Future<void> dispose() async {
    playing = false;
    disposed = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late JsonStore store;
  late List<FakeLoop> players;
  late ProviderContainer c;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('scene_sound');
    store = await JsonStore.open(dir);
    players = [];
    SceneSoundController.playerFactory = () => FakeLoop(players);
    SceneSoundController.fade = Duration.zero;
    c = ProviderContainer(overrides: [storeProvider.overrideWithValue(store)]);
    c.read(settingsProvider.notifier).update((s) => s.copyWith(sceneSoundVolume: 0.5));
  });

  tearDown(() async {
    c.dispose();
    await store.flush();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  List<FakeLoop> live() => players.where((p) => !p.disposed).toList();
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('every scene has a sound, for every tier, from files that ship with the app and are credited', () {
    final credits = File('assets/sounds/CREDITS.md').readAsStringSync();
    for (final vibe in Vibe.values) {
      final layers = sceneSounds[vibe]!;
      expect(layers, isNotEmpty, reason: vibe.name);
      expect(sceneSoundLabels[vibe], isNotEmpty);
      for (final l in layers) {
        expect(File(l.asset).existsSync(), isTrue, reason: l.asset);
        expect(credits, contains('`${l.name}.ogg`'), reason: '${l.name} must be credited');
        expect(l.volume, inInclusiveRange(0.05, 1.0));
      }
    }
    expect(File('pubspec.yaml').readAsStringSync(), contains('- assets/sounds/'));
    // On by default, for everyone (no paid gate).
    expect(const AppSettings().sceneSound, isTrue);
  });

  test('plays the scene mix at the reader volume and crossfades to a new scene', () async {
    final sound = c.read(sceneSoundProvider.notifier);
    await sound.play(Vibe.rain);
    expect(live().map((p) => p.asset), ['assets/sounds/rain.ogg', 'assets/sounds/city.ogg']);
    expect(live().every((p) => p.playing), isTrue);
    expect(live().first.volume, closeTo(0.85 * 0.5, 1e-9));
    expect(c.read(sceneSoundProvider).scene, Vibe.rain);

    // Same scene again: nothing restarts.
    await sound.play(Vibe.rain);
    expect(players, hasLength(2));

    // The AI's Auto scene moves to the café: old layers released, new ones in.
    await sound.play(Vibe.cafe);
    await settle();
    expect(live().map((p) => p.asset), ['assets/sounds/cafe.ogg', 'assets/sounds/rain.ogg']);
    expect(players.take(2).every((p) => p.disposed), isTrue);
  });

  test('mute, volume, read-aloud ducking and background pause', () async {
    final sound = c.read(sceneSoundProvider.notifier);
    await sound.play(Vibe.snow);
    final fire = live().first;
    expect(fire.asset, 'assets/sounds/fireplace.ogg');

    await sound.duck(true);
    expect(fire.volume, closeTo(0.7 * 0.5 * 0.3, 1e-9));
    await sound.duck(false);

    c.read(settingsProvider.notifier).update((s) => s.copyWith(sceneSoundVolume: 1));
    await sound.applyVolume();
    expect(fire.volume, closeTo(0.7, 1e-9));

    await sound.pause();
    expect(live().any((p) => p.playing), isFalse);
    await sound.resume();
    expect(live().every((p) => p.playing), isTrue);

    // Muted (to play your own music): everything stops and nothing restarts.
    c.read(settingsProvider.notifier).update((s) => s.copyWith(sceneSound: false));
    await sound.play(Vibe.snow);
    await settle();
    expect(live(), isEmpty);
    await sound.resume();
    expect(live(), isEmpty);
  });

  test('a scene change during a crossfade leaves no player behind', () async {
    SceneSoundController.fade = const Duration(milliseconds: 200);
    final sound = c.read(sceneSoundProvider.notifier);
    await sound.play(Vibe.ocean);
    final second = sound.play(Vibe.night); // starts fading ocean out
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final third = sound.play(Vibe.meadow); // cuts that fade short
    await Future.wait([second, third]);
    await settle();
    expect(live().map((p) => p.asset), ['assets/sounds/birds.ogg', 'assets/sounds/wind.ogg']);
    await sound.stop();
    await settle();
    expect(live(), isEmpty);
  });

  test('settings: an old soundtrack switched off stays off; otherwise scene sound is on', () {
    expect(AppSettings.fromJson({'soundtrack': false}).sceneSound, isFalse);
    expect(AppSettings.fromJson({'soundtrack': true, 'musicVolume': 0.35}).sceneSound, isTrue);
    expect(AppSettings.fromJson({}).sceneSound, isTrue);
    expect(AppSettings.fromJson({'sceneSoundVolume': 3}).sceneSoundVolume, 1);
    final round = AppSettings.fromJson(const AppSettings(sceneSound: false, sceneSoundVolume: 0.3).toJson());
    expect((round.sceneSound, round.sceneSoundVolume), (false, 0.3));
  });
}
