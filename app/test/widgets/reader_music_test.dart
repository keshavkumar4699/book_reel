import 'dart:io';

import 'package:book_reel/core/segmentation/rule_segmenter.dart';
import 'package:book_reel/data/habit.dart';
import 'package:book_reel/data/json_store.dart';
import 'package:book_reel/data/library.dart';
import 'package:book_reel/data/settings.dart';
import 'package:book_reel/data/settings_provider.dart';
import 'package:book_reel/data/store_provider.dart';
import 'package:book_reel/features/reader/reader_screen.dart';
import 'package:book_reel/services/local_voice.dart';
import 'package:book_reel/services/music.dart';
import 'package:book_reel/services/read_aloud.dart';
import 'package:book_reel/services/screen_awake.dart';
import 'package:book_reel/ui/kit.dart';
import 'package:book_reel/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fake_voice.dart';
import '../silent_music.dart';

/// The music in the Reading tab, as the tab comes and goes: a book opened
/// from another tab plays, and reading aloud never leaves it silent.
void main() {
  final dirs = <Directory>[];
  late List<String> sounds;
  late List<SilentPlayer> players;
  setUp(() {
    quietReader();
    sounds = [];
    players = [];
    MusicPlayer.playerFactory = () => SilentPlayer(sounds, players);
  });
  tearDownAll(() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final d in dirs) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
  });

  /// The Reading tab: [shown] is whether it's the tab on screen, [book]
  /// which reader it holds (a new one starts a new reader, as a new book does).
  Future<(ProviderContainer, ValueNotifier<bool>, ValueNotifier<String>)> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('reader_music');
    dirs.add(dir);
    late ProviderContainer c;
    late String bookId;
    await tester.runAsync(() async {
      c = ProviderContainer(overrides: [storeProvider.overrideWithValue(await JsonStore.open(dir))]);
      c.read(settingsProvider.notifier).update((s) => s.copyWith(
          onboardingDone: true, goalSetupDone: true, gestureTutorialSeen: true, animatedBackground: false, cardLength: CardLength.standard));
      bookId = (await c.read(libraryProvider.notifier).ensureStarterBook())!.id;
    });
    addTearDown(c.dispose);
    final shown = ValueNotifier(true), book = ValueNotifier('first');
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: buildAppTheme(Kit.forScene(Vibe.forest, ReadingTheme.of(ReadingThemeId.paper))),
        home: ListenableBuilder(
          listenable: Listenable.merge([shown, book]),
          builder: (context, _) => TickerMode(
            enabled: shown.value,
            child: ReaderScreen(key: ValueKey(book.value), bookId: bookId, embedded: true),
          ),
        ),
      ),
    ));
    await loaded(tester);
    return (c, shown, book);
  }

  testWidgets('a book opened from another tab plays its music, whether it opens in sight or out of it', (tester) async {
    final (c, shown, book) = await open(tester);
    expect(players.last.playing, isTrue);

    // To the Library: the music holds.
    shown.value = false;
    await tester.pump();
    expect(players.last.playing, isFalse);

    // A book picked there: the Reading tab comes back with it.
    shown.value = true;
    book.value = 'second';
    await tester.pump();
    await loaded(tester);
    expect(c.read(musicProvider).playing, isTrue);
    expect(players.last.playing, isTrue, reason: 'heard, not just shown as playing');

    // A book that opens while another tab is on screen plays once it's shown.
    shown.value = false;
    await tester.pump();
    book.value = 'third';
    await tester.pump();
    await loaded(tester);
    expect(players.last.playing, isFalse);
    shown.value = true;
    await tester.pump();
    await tester.pump();
    expect(players.last.playing, isTrue);
  });

  testWidgets('the natural voice reads over quieter music; afterwards the music is back up and playing', (tester) async {
    final voiceDir = Directory.systemTemp.createTempSync('voice');
    dirs.add(voiceDir);
    final speech = FakeSpeechPlayer();
    final (player, cache, installer, root, engine) =
        (ReadAloud.playerFactory, ReadAloud.cacheRoot, LocalVoiceController.installer, LocalVoiceController.root, LocalSpeech.factory);
    addTearDown(() {
      ReadAloud.playerFactory = player;
      ReadAloud.cacheRoot = cache;
      LocalVoiceController.installer = installer;
      LocalVoiceController.root = root;
      LocalSpeech.factory = engine;
    });
    ReadAloud.playerFactory = () => speech;
    ReadAloud.cacheRoot = () async => voiceDir;
    LocalVoiceController.installer = InstalledVoice();
    LocalVoiceController.root = () async => voiceDir;
    LocalSpeech.factory = (_) => FakeLocalEngine();
    final (c, _, _) = await open(tester);
    c.read(settingsProvider.notifier).update((s) => s.copyWith(naturalVoice: true));
    c.read(localVoiceProvider);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    expect(c.read(localVoiceProvider).ready, isTrue);
    final music = players.last, full = c.read(settingsProvider).musicVolume;
    Future<void> until(bool Function() done) async {
      for (var i = 0; i < 60 && !done(); i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(done(), isTrue);
    }

    await tester.fling(find.byType(PageView), const Offset(0, -500), 1500);
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('Read aloud').first);
    await tester.pump(const Duration(milliseconds: 400)); // past the wait for a double tap
    await until(() => speech.played.isNotEmpty);
    expect(music.volume, closeTo(full * 0.3, 1e-9), reason: 'quieter under the voice');
    expect(music.playing, isTrue);

    // Back to the chapter's title: that reel stops being read, and listening
    // carries on into the chapter by itself.
    speech.stopped = false;
    await tester.fling(find.byType(PageView), const Offset(0, 500), 1500);
    await settle(tester);
    expect(speech.stopped, isTrue);
    expect(music.volume, full);
    final heard = speech.played.length;
    await tester.pump(ReaderScreen.passTitleAfter);
    await until(() => speech.played.length > heard);

    // Listening stopped: the music is back up, and playing.
    await tester.tap(find.bySemanticsLabel('Stop reading aloud').first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(music.volume, full);
    expect(music.playing, isTrue);
  });

  testWidgets('reels read aloud hands-free count as read, keep the screen on, and go on with it off', (tester) async {
    final voiceDir = Directory.systemTemp.createTempSync('voice');
    dirs.add(voiceDir);
    final speech = FakeSpeechPlayer();
    final messenger = tester.binding.defaultBinaryMessenger;
    final (player, cache, installer, root, engine) =
        (ReadAloud.playerFactory, ReadAloud.cacheRoot, LocalVoiceController.installer, LocalVoiceController.root, LocalSpeech.factory);
    addTearDown(() {
      ReadAloud.playerFactory = player;
      ReadAloud.cacheRoot = cache;
      LocalVoiceController.installer = installer;
      LocalVoiceController.root = root;
      LocalSpeech.factory = engine;
      ReaderScreen.clock = DateTime.now;
      messenger.setMockMethodCallHandler(ScreenAwake.channel, null);
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });
    // What the phone is asked: keep the screen on, and tick under the thumb.
    final awake = <bool>[];
    messenger.setMockMethodCallHandler(ScreenAwake.channel, (call) async {
      if (call.method == 'keepOn') awake.add(call.arguments as bool);
      return null;
    });
    var ticks = 0;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') ticks++;
      return null;
    });
    ReadAloud.playerFactory = () => speech;
    ReadAloud.cacheRoot = () async => voiceDir;
    LocalVoiceController.installer = InstalledVoice();
    LocalVoiceController.root = () async => voiceDir;
    LocalSpeech.factory = (_) => FakeLocalEngine();
    var now = DateTime(2026, 11, 17, 9);
    ReaderScreen.clock = () => now;
    final (c, _, _) = await open(tester);
    c.read(settingsProvider.notifier).update((s) => s.copyWith(naturalVoice: true));
    c.read(localVoiceProvider);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    expect(c.read(localVoiceProvider).ready, isTrue);
    int verified() => c.read(habitProvider).totalVerifiedCards;
    final pager = tester.widget<PageView>(find.byType(PageView)).controller!;
    int page() => pager.page!.round();

    await tester.fling(find.byType(PageView), const Offset(0, -500), 1500);
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('Read aloud').first);
    await tester.pump(const Duration(milliseconds: 400));
    expect(awake, [true], reason: 'the screen stays on while reels are read aloud');
    ticks = 0;

    /// Reads aloud, untouched, until [pages] reels have turned: each part
    /// takes as long to hear as it would to read. [frames] is whether the
    /// app is drawing (not with the screen off).
    Future<void> listen(int pages, {bool frames = true}) async {
      final until = page() + pages;
      for (var i = 0; i < 60 && page() < until; i++) {
        final heard = speech.played.length;
        for (var k = 0; k < 40 && speech.played.length == heard; k++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
          await tester.pump(const Duration(milliseconds: 50));
        }
        now = now.add(const Duration(seconds: 12));
        speech.finish();
        for (var k = 0; k < 8; k++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
          await tester.pump(const Duration(milliseconds: 100));
        }
      }
      expect(page(), until, reason: frames ? 'the reels turn by themselves' : 'they turn with the screen off too');
    }

    final first = page();
    await listen(8);
    final inSight = verified();
    expect(inSight, greaterThanOrEqualTo(2), reason: 'the reels heard count as read (a card is a few reels)');
    expect(ticks, 0, reason: 'no tick for a reel no finger turned');
    expect(awake, [true]);

    // The screen goes off (or another app comes up): nothing is drawn, yet
    // listening goes on, the reels turn as they're read, and they count,
    // the time in the background with them.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(tester.binding.framesEnabled, isFalse);
    await listen(8, frames: false);
    expect(verified(), greaterThan(inSight), reason: 'read aloud with the screen off counts');
    expect(ticks, 0, reason: 'and the phone in your pocket doesn’t tick');
    final away = verified();

    // Back: the reel being heard carries on where it is, its time away
    // counted with it.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await listen(4);
    expect(verified(), greaterThanOrEqualTo(away));
    expect(page(), first + 20);

    // Stopped: the screen may time out again.
    await tester.tap(find.bySemanticsLabel('Stop reading aloud').first);
    await tester.pump(const Duration(milliseconds: 400));
    expect(awake, [true, false]);
    await settle(tester);
  });

  testWidgets('a voice that can’t read stops listening, and the music comes back up', (tester) async {
    final (c, _, _) = await open(tester);
    final volume = c.read(settingsProvider).musicVolume;
    await tester.fling(find.byType(PageView), const Offset(0, -500), 1500);
    await settle(tester);
    // No voice works in tests: the phone's own voice fails as it starts.
    await tester.tap(find.bySemanticsLabel('Read aloud').first);
    await tester.pump(const Duration(milliseconds: 400)); // past the wait for a double tap
    for (var i = 0; i < 20 && find.text('Couldn’t read this aloud').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(find.text('Couldn’t read this aloud'), findsOneWidget);
    expect(find.bySemanticsLabel('Read aloud'), findsWidgets, reason: 'Listen is off again');
    expect(find.bySemanticsLabel('Stop reading aloud'), findsNothing);
    expect(players.last.playing, isTrue);
    expect(players.last.volume, volume, reason: 'not left quieter');
    await tester.pump(const Duration(seconds: 4)); // the toast times out
    await settle(tester);
  });
}

/// The book's reels are on screen (they load off the main thread).
Future<void> loaded(WidgetTester tester) async {
  for (var i = 0; i < 25 && find.byType(PageView).evaluate().isEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
  }
  expect(find.byType(PageView), findsOneWidget);
  await tester.pump();
  await tester.pump();
}

Future<void> settle(WidgetTester tester) =>
    tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
