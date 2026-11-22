import 'dart:io';

import 'package:book_reel/data/json_store.dart';
import 'package:book_reel/data/settings_provider.dart';
import 'package:book_reel/data/store_provider.dart';
import 'package:book_reel/services/music.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../silent_music.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late JsonStore store;
  late List<SilentPlayer> players;
  late List<String> log;
  late ProviderContainer c;

  const mine = [Track('assets/sounds/music/a.mp3', 'A'), Track('assets/sounds/music/b.mp3', 'B'), Track('assets/sounds/music/c.mp3', 'C')];

  Future<ProviderContainer> container({List<Track> tracks = mine}) async {
    final c = ProviderContainer(overrides: [
      storeProvider.overrideWithValue(store),
      tracksProvider.overrideWith((ref) async => tracks),
    ]);
    c.read(settingsProvider.notifier).update((s) => s.copyWith(musicVolume: 0.5));
    return c;
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('music');
    store = await JsonStore.open(dir);
    players = [];
    log = [];
    MusicPlayer.playerFactory = () => SilentPlayer(log, players);
    MusicPlayer.fade = Duration.zero;
    MusicPlayer.random = FirstPick();
    c = await container();
  });

  tearDown(() async {
    c.dispose();
    await store.flush();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('every track in the sounds folders is music; names read as words', () {
    expect(tracksFrom(['assets/sounds/CREDITS.md', 'assets/sounds/music/README.md']), isEmpty);
    final tracks = tracksFrom([
      'assets/sounds/music/02_Gymnopedie.ogg',
      'assets/sounds/music/01 - Clair_de_lune.mp3',
      'assets/sounds/music/notes.txt',
      'assets/sounds/Lukrembo - Jay (freetouse.com).mp3',
      'assets/sounds/massobeats - daydream (freetouse.com).mp3',
      'assets/other/elsewhere.mp3',
    ]);
    expect(tracks.map((t) => t.label), ['Clair de lune', 'Gymnopedie', 'Jay · Lukrembo', 'Daydream · massobeats']);
    expect(tracks.every((t) => !t.loop), isTrue, reason: 'music plays through, then the next');
  });

  test('a book opens on a random track; previous and next wrap around; pause and play', () async {
    MusicPlayer.random = _Fixed(1);
    final music = c.read(musicProvider.notifier);
    final owner = Object();
    await music.start(owner);
    expect(c.read(musicProvider).track!.title, 'B');
    expect(c.read(musicProvider).playing, isTrue);
    expect(players.single.asset, 'assets/sounds/music/b.mp3');
    expect(players.single.playing, isTrue);
    expect(players.single.volume, 0.5);
    await music.next();
    await music.next();
    expect(c.read(musicProvider).track!.title, 'A', reason: 'after the last, the first');
    await music.previous();
    expect(c.read(musicProvider).track!.title, 'C');
    expect(players, hasLength(1), reason: 'one player, reused');
    await music.toggle();
    expect((c.read(musicProvider).playing, players.single.playing), (false, false));
    await music.toggle();
    expect((c.read(musicProvider).playing, players.single.playing), (true, true));
    expect(log.where((e) => e.startsWith('load')), hasLength(4), reason: 'play after pause carries on, no reload');
  });

  test('a track that ends moves on to the next; a loop repeats', () async {
    final music = c.read(musicProvider.notifier);
    await music.start(Object());
    expect(players.single.loop, isFalse);
    players.single.complete!();
    await Future<void>.delayed(Duration.zero);
    expect(c.read(musicProvider).track!.title, 'B');

    final looping = await container(tracks: const [Track('assets/sounds/rain.ogg', 'Rain', loop: true)]);
    addTearDown(looping.dispose);
    await looping.read(musicProvider.notifier).start(Object());
    expect(players.last.loop, isTrue);
  });

  test('music off: a book opens in silence, play is a tap away', () async {
    c.read(settingsProvider.notifier).update((s) => s.copyWith(music: false));
    final music = c.read(musicProvider.notifier);
    await music.start(Object());
    expect(c.read(musicProvider).playing, isFalse);
    expect(players.single.playing, isFalse);
    expect(c.read(musicProvider).track, isNotNull, reason: 'loaded and ready');
    await music.toggle();
    expect(players.single.playing, isTrue);
  });

  test('out of sight it holds; back, it carries on; quieter under read-aloud', () async {
    final music = c.read(musicProvider.notifier);
    await music.start(Object());
    await music.hold();
    expect(players.single.playing, isFalse);
    expect(c.read(musicProvider).playing, isTrue, reason: 'still "playing" for the button');
    await music.release();
    expect(players.single.playing, isTrue);
    await music.toggle(); // paused by the reader
    await music.hold();
    await music.release();
    expect(players.single.playing, isFalse, reason: 'a pause chosen by the reader stays');
    await music.toggle();
    await music.duck(true);
    expect(players.single.volume, closeTo(0.15, 1e-9));
    await music.duck(false);
    expect(players.single.volume, 0.5);
  });

  test('only the reader that started the music stops it', () async {
    final music = c.read(musicProvider.notifier);
    final oldBook = Object(), newBook = Object();
    await music.start(oldBook);
    await music.start(newBook); // the new book's reader starts before the old one is gone
    await music.stop(oldBook);
    expect(players.last.playing, isTrue);
    await music.stop(newBook);
    expect(players.last.disposed, isTrue);
    expect(c.read(musicProvider).playing, isFalse);
  });
}

class _Fixed extends FirstPick {
  _Fixed(this.value);
  final int value;
  @override
  int nextInt(int max) => value % max;
}
