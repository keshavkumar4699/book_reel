import 'dart:io';

import 'package:book_reel/core/models/reel_card.dart';
import 'package:book_reel/core/segmentation/feed_builder.dart';
import 'package:book_reel/core/segmentation/rule_segmenter.dart';
import 'package:book_reel/data/habit.dart';
import 'package:book_reel/data/json_store.dart';
import 'package:book_reel/data/library.dart';
import 'package:book_reel/data/notebook.dart';
import 'package:book_reel/data/segments.dart';
import 'package:book_reel/data/settings.dart';
import 'package:book_reel/data/settings_provider.dart';
import 'package:book_reel/data/store_provider.dart';
import 'package:book_reel/features/reader/cards/text_card.dart';
import 'package:book_reel/features/reader/reader_screen.dart';
import 'package:book_reel/features/share/share_sheet.dart';
import 'package:book_reel/services/scene_sound.dart';
import 'package:book_reel/ui/kit.dart';
import 'package:book_reel/ui/theme.dart';
import 'package:book_reel/ui/typography.dart';
import 'package:book_reel/ui/vibes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records what would be played (tests have no audio plugin).
class SilentLoop implements LoopPlayer {
  SilentLoop(this.log);
  final List<String> log;
  @override
  Future<void> load(String asset) async => log.add(asset);
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> dispose() async => log.add('released');
}

void main() {
  final sounds = <String>[];
  setUp(() {
    sounds.clear();
    SceneSoundController.playerFactory = () => SilentLoop(sounds);
    SceneSoundController.fade = Duration.zero;
  });

  testWidgets('reader opens the starter book and swipes from the chapter card to text', (tester) async {
    final dir = Directory.systemTemp.createTempSync('bookreel_widget');
    late ProviderContainer container;
    late String bookId;
    await tester.runAsync(() async {
      final store = await JsonStore.open(dir);
      container = ProviderContainer(overrides: [storeProvider.overrideWithValue(store)]);
      container.read(settingsProvider.notifier).update(
          (s) => s.copyWith(onboardingDone: true, goalSetupDone: true, animatedBackground: false, cardLength: CardLength.standard));
      bookId = (await container.read(libraryProvider.notifier).ensureStarterBook())!.id;
    });

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildAppTheme(Kit.forScene(Vibe.forest, ReadingTheme.of(ReadingThemeId.paper))), home: ReaderScreen(bookId: bookId)),
    ));
    // Book content and segments load in isolates: let real async work finish.
    for (var i = 0; i < 20 && find.text('Swipe up to begin').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
    }
    expect(find.text('CHAPTER 1'), findsOneWidget);
    expect(find.text('Down the Rabbit-Hole'), findsOneWidget);
    expect(find.text('Swipe up to begin'), findsOneWidget);

    // The scene's own sound plays (forest: wind, birds, crickets), for free users too.
    expect(sounds, ['assets/sounds/wind.ogg', 'assets/sounds/birds.ogg', 'assets/sounds/crickets.ogg']);

    // First run shows the gesture guide once.
    expect(find.text('Read like you scroll'), findsOneWidget);
    // The guide scrolls on short screens (the test window is 800 x 600).
    await tester.ensureVisible(find.text('Got it'));
    await tester.tap(find.text('Got it'));
    await tester.pump();
    expect(find.text('Read like you scroll'), findsNothing);
    expect(container.read(settingsProvider).gestureTutorialSeen, isTrue);

    // Focus mode: a book opens with nothing on screen but the reel.
    expect(find.bySemanticsLabel('Focus: hide the controls'), findsNothing);

    // A long press on empty space opens the options; the scene sound is a switch there.
    await tester.longPressAt(const Offset(30, 400));
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
    for (final o in ['Theme', 'Scene sound', 'Contents', 'Page mode', 'Daily goal', 'Gestures', 'Settings', 'This cut feels wrong']) {
      expect(find.text(o), findsOneWidget, reason: o);
    }
    await tester.tap(find.text('Scene sound'));
    await tester.pump();
    await tester.pump();
    expect(container.read(settingsProvider).sceneSound, isFalse);
    expect(sounds.where((x) => x == 'released'), hasLength(3));
    await tester.tap(find.text('Scene sound'));
    await tester.pump();
    await tester.pump();
    expect(container.read(settingsProvider).sceneSound, isTrue);
    expect(sounds.where((x) => x.endsWith('.ogg')), hasLength(6));
    await tester.tapAt(const Offset(20, 20)); // outside the sheet
    await tester.pump(const Duration(seconds: 4)); // the toasts time out
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
    expect(find.text('This cut feels wrong'), findsNothing);

    // A tap on empty space shows the controls; they stay until the eye hides them.
    await tester.tapAt(const Offset(30, 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
    expect(find.bySemanticsLabel('Focus: hide the controls'), findsOneWidget);
    expect(container.read(readerChromeProvider), isTrue);

    await tester.fling(find.byType(PageView), const Offset(0, -500), 1500);
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
    expect(find.textContaining('Alice was beginning to get very tired', findRichText: true), findsOneWidget);
    expect(find.bySemanticsLabel('Save'), findsOneWidget);
    expect(find.bySemanticsLabel('Share'), findsOneWidget);
    // The share button is the reels-style arrow, not the system share glyph.
    expect(find.byType(ShareArrowIcon), findsOneWidget);
    expect(find.byIcon(Icons.ios_share), findsNothing);

    // The rail: like, save, note, share, listen, streak, goal, options.
    expect(find.bySemanticsLabel('Write a note'), findsOneWidget);
    expect(find.bySemanticsLabel('Options'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel(RegExp(r'day streak\. Open streak$')));
    // Buttons on a reel answer after the double-tap window.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
    expect(find.text('Your streak'), findsOneWidget);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
    await tester.tap(find.bySemanticsLabel(RegExp(r'^Today.s goal .*Open goal$')));
    // Buttons on a reel answer after the double-tap window.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
    expect(find.text('Days per week'), findsOneWidget);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));

    // The note box opens empty, for your own thoughts; they go to the Notebook.
    await tester.tap(find.bySemanticsLabel('Write a note'));
    // Buttons on a reel answer after the double-tap window.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
    expect(find.text('Your thoughts'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Curiosity starts the whole story.');
    await tester.tap(find.text('Save').last); // the sheet's button (the rail has a "Save" too)
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
    final thought = container.read(notebookProvider).reflections.single;
    expect(thought.text, 'Curiosity starts the whole story.');
    expect(thought.quote, contains('Alice was beginning'));
    await tester.pump(const Duration(seconds: 4));

    // The eye hides everything again.
await tester.tap(find.bySemanticsLabel('Focus: hide the controls'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
    expect(tester.widgetList<FadeChrome>(find.byType(FadeChrome)).every((c) => !c.visible), isTrue, reason: 'rail, book row and top bar hidden');
    expect(container.read(readerChromeProvider), isFalse);

    // Double-tap anywhere on the post likes it.
    final post = find.byType(PostCard);
    await tester.tap(post);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(post);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 1));
    final card = tester.widget<PostCard>(post);
    expect(container.read(notebookProvider).liked, contains('$bookId|${card.card.startSid}'));

    // Swipe left saves.
    await tester.drag(post, const Offset(-200, 0));
    await tester.pump();
    expect(find.text('Saved to your Notebook 🔖'), findsOneWidget);
    expect(container.read(notebookProvider).isSaved(bookId, card.card.startSid), isTrue);
    await tester.pump(const Duration(seconds: 3)); // let the toast time out

    await tester.runAsync(() async => dir.deleteSync(recursive: true));
  });

  testWidgets('a tap on a word shows its meaning; a long press highlights it and the handles extend it', (tester) async {
    tester.view.physicalSize = const Size(1236, 2745);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('bookreel_handles');
    late ProviderContainer container;
    late String bookId;
    await tester.runAsync(() async {
      final store = await JsonStore.open(dir);
      container = ProviderContainer(overrides: [storeProvider.overrideWithValue(store)]);
      container.read(settingsProvider.notifier).update((s) => s.copyWith(
          onboardingDone: true, goalSetupDone: true, gestureTutorialSeen: true, animatedBackground: false, cardLength: CardLength.standard));
      bookId = (await container.read(libraryProvider.notifier).ensureStarterBook())!.id;
    });
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildAppTheme(Kit.forScene(Vibe.forest, ReadingTheme.of(ReadingThemeId.paper))), home: ReaderScreen(bookId: bookId)),
    ));
    for (var i = 0; i < 20 && find.text('Swipe up to begin').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
    }
    await tester.fling(find.byType(PageView), const Offset(0, -500), 1500);
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
    final lines = find.descendant(of: find.byType(ReelText), matching: find.byType(RichText));
    final first = tester.getRect(lines.first);

    // A tap on a word: its meaning.
    await tester.tapAt(first.topLeft + const Offset(30, 12));
    await tester.pump(const Duration(milliseconds: 400)); // past the double-tap window
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
    expect(find.text('Add to word list'), findsOneWidget);
    expect(container.read(notebookProvider).highlights, isEmpty, reason: 'a tap no longer highlights');
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));

    // A long press on a word: the highlighter starts on that word, with handles and a toolbar.
    await tester.longPressAt(first.topLeft + const Offset(30, 12));
    await tester.pump(const Duration(milliseconds: 400));
    final created = container.read(notebookProvider).highlights.single;
    expect(created.start, 0, reason: 'just the word');
    expect(created.end, lessThan(15));
    expect(find.bySemanticsLabel('Start of highlight'), findsOneWidget);
    expect(find.bySemanticsLabel('End of highlight'), findsOneWidget);
    expect(find.bySemanticsLabel('Done'), findsOneWidget);
    final page = tester.state<State>(find.byType(PageView)).context;
    expect((tester.widget<PageView>(find.byType(PageView)).physics), isA<NeverScrollableScrollPhysics>(),
        reason: 'the reel holds still while the highlight is adjusted');

    // Drag the end handle along the first line: the highlight grows by whole words.
    final end = tester.getCenter(find.bySemanticsLabel('End of highlight'));
    final target = first.topLeft + Offset(first.width * 0.7, first.height / 2);
    final gesture = await tester.startGesture(end);
    for (var k = 1; k <= 8; k++) {
      await gesture.moveTo(Offset.lerp(end, target, k / 8)!);
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Done'));
    await tester.pump();
    final saved = container.read(notebookProvider).highlights.single;
    expect(saved.id, created.id);
    expect(saved.start, 0);
    expect(saved.end, greaterThan(created.end!));
    expect(saved.text, startsWith(created.text));
    expect(saved.text, isNot(endsWith(' ')), reason: 'snapped to the end of a word');
    expect(find.bySemanticsLabel('Done'), findsNothing);
    expect((tester.widget<PageView>(find.byType(PageView)).physics), isNot(isA<NeverScrollableScrollPhysics>()));
    expect(page.mounted, isTrue);

    // A long press on the highlight picks it up again; the toolbar removes it.
    await tester.longPressAt(first.topLeft + const Offset(30, 12));
    await tester.pump(const Duration(milliseconds: 400));
    expect(container.read(notebookProvider).highlights, hasLength(1), reason: 'no second highlight');
    await tester.tap(find.bySemanticsLabel('Remove highlight'));
    await tester.pump();
    expect(container.read(notebookProvider).highlights, isEmpty);

    await tester.runAsync(() async => dir.deleteSync(recursive: true));
  });

  testWidgets('a hero line gets its own reel; text reels keep one size, the book fonts and room to breathe', (tester) async {
    // A phone-sized screen (412 x 915 dp).
    tester.view.physicalSize = const Size(1236, 2745);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('bookreel_spot');
    late ProviderContainer container;
    late String bookId;
    late List<FeedItem> feed;
    await tester.runAsync(() async {
      final store = await JsonStore.open(dir);
      container = ProviderContainer(overrides: [storeProvider.overrideWithValue(store)]);
      container.read(settingsProvider.notifier).update((s) => s.copyWith(
          onboardingDone: true, goalSetupDone: true, gestureTutorialSeen: true, animatedBackground: false, vibe: Vibe.forest));
      bookId = (await container.read(libraryProvider.notifier).ensureStarterBook())!.id;
      final book = await container.read(bookContentProvider(bookId).future);
      final segments = await container.read(segmentsProvider((bookId: bookId, length: CardLength.snack)).future);
      feed = buildFeed(book, segments, const FeedOptions(recallEvery: 15));
    });
    // A card shown as text · spotlight · text.
    final spotAt = Iterable<int>.generate(feed.length).firstWhere((i) =>
        feed[i].spotlight && i > 0 && identical(feed[i - 1].card, feed[i].card) && identical(feed[i + 1].card, feed[i].card));
    final settings = container.read(settingsProvider);
    final voice = voiceStyles[voiceByName(container.read(libraryProvider).single.voice)]!;
    final palette = scenePalettes[Vibe.forest]!;

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildAppTheme(Kit.forScene(Vibe.forest, ReadingTheme.of(ReadingThemeId.paper))),
        home: ReaderScreen(bookId: bookId, startSid: feed[spotAt - 1].anchorSid),
      ),
    ));
    for (var i = 0; i < 20 && find.byType(PostCard).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
    }
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));

    List<TextStyle> lineStyles() => [
          for (final r in tester.widgetList<RichText>(find.descendant(of: find.byType(ReelText), matching: find.byType(RichText))))
            ((r.text as TextSpan).children!.single as TextSpan).style ?? ((r.text as TextSpan).children!.single as TextSpan).children!.first.style!,
        ];

    // 1. The text reel before the spotlight.
    expect(tester.widget<PostCard>(find.byType(PostCard)).spotlight, isFalse);
    final body = lineStyles();
    expect(body, isNotEmpty);
    // One size for every line: the reader's size, never enlarged to fill the screen.
    expect(body.map((s) => s.fontSize).toSet(), {settings.fontSize * voice.bodyScale});
    expect(body.map((s) => s.fontFamily).toSet(), {voice.body});
    // Colours come from the scene's palette (no pure white).
    expect(body.map((s) => s.color).toSet().difference({palette.ink, palette.emphasis}), isEmpty);
    // The text column sits well inside the screen.
    final area = tester.getRect(find.byType(ReelText));
    expect(area.left, greaterThanOrEqualTo(28));
    expect(area.right, lessThanOrEqualTo(412 - 72));
    expect(area.top, greaterThanOrEqualTo(110));
    expect(area.bottom, lessThanOrEqualTo(915 - 110));
    final lines = find.descendant(of: find.byType(ReelText), matching: find.byType(RichText));
    final textTop = tester.getRect(lines.first).top, textBottom = tester.getRect(lines.last).bottom;
    expect(textBottom - textTop, lessThan(915 * 0.62), reason: 'a snack reel leaves the scene visible');
    expect(textTop, greaterThanOrEqualTo(area.top));
    expect(textBottom, lessThanOrEqualTo(area.bottom + 0.5));

    Future<void> next() async {
      // Real time must pass for the reading-time check.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 450)));
      await tester.fling(find.byType(PageView), const Offset(0, -500), 1500);
      await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
    }

    int recorded() {
      final today = container.read(habitProvider).today(DateTime.now());
      return today.verifiedCards + today.skimmedCards;
    }

    // 2. The spotlight: one sentence, the display face, one larger size.
    await next();
    final spot = tester.widget<PostCard>(find.byType(PostCard));
    expect(spot.spotlight, isTrue);
    expect(spot.sentences, hasLength(1));
    final spotSpans = ((tester.widget<RichText>(lines.first).text as TextSpan).children!.single as TextSpan).children!.cast<TextSpan>();
    expect(spotSpans.map((s) => s.style!.fontFamily).toSet(), {voice.display});
    final spotSize = spotSpans.map((s) => s.style!.fontSize!).toSet();
    expect(spotSize, hasLength(1), reason: 'the whole line has one size');
    expect(spotSize.single, greaterThan(settings.fontSize * voice.bodyScale));
    expect(spotSize.single, lessThanOrEqualTo(44 * voice.displayScale + 0.01));
    expect(spotSpans.map((s) => s.text).join(), spot.sentences.single.sentence.text);
    expect(recorded(), 0, reason: 'the card is not finished yet');

    // 3. The rest of the card, then on to the next one: the card counts once.
    await next();
    expect(tester.widget<PostCard>(find.byType(PostCard)).spotlight, isFalse);
    expect(recorded(), 0);
    await next();
    expect(recorded(), 1);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() async => dir.deleteSync(recursive: true));
  });

  testWidgets('share card art limits copyrighted quotes and renders progress', (tester) async {
    final sentences = List.generate(20, (i) => 'This is sentence number $i of the card.');
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: ShareCardArt(
          content: QuoteShare(sentences: sentences, bookTitle: 'Book', author: 'Author', publicDomain: false),
          template: ShareTemplate.paper,
          aspect: ShareAspect.story,
        ),
      ),
    ));
    expect(find.textContaining('sentence number 0'), findsOneWidget);
    expect(find.textContaining('sentence number 19'), findsNothing);
    expect(find.text('— Author'), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(
      home: Center(
        child: ShareCardArt(
          content: ProgressShare(headline: '7-day streak', lines: ['70 cards']),
          template: ShareTemplate.ember,
          aspect: ShareAspect.square,
        ),
      ),
    ));
    expect(find.text('7-day streak'), findsOneWidget);
  });
}
