import 'dart:io';

import 'package:book_reel/app.dart';
import 'package:book_reel/core/segmentation/rule_segmenter.dart';
import 'package:book_reel/data/json_store.dart';
import 'package:book_reel/data/library.dart';
import 'package:book_reel/data/notebook.dart';
import 'package:book_reel/data/segments.dart';
import 'package:book_reel/data/settings_provider.dart';
import 'package:book_reel/data/store_provider.dart';
import 'package:book_reel/features/notebook/notebook_screen.dart';
import 'package:book_reel/features/reader/cards/text_card.dart';
import 'package:book_reel/features/reader/reader_screen.dart';
import 'package:book_reel/features/shell/home_shell.dart';
import 'package:book_reel/services/music.dart';
import 'package:book_reel/ui/kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../silent_music.dart';

/// A saved, liked or highlighted reel opens over the screen it was tapped
/// on: back comes back there, and the book you're reading keeps its place,
/// so the Reading tab and "Continue reading" open the reel you were on.
void main() {
  final dirs = <Directory>[];
  late List<String> played;
  setUp(() {
    played = [];
    quietReader(played);
  });
  tearDownAll(() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final d in dirs) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
  });

  Future<void> settle(WidgetTester tester) =>
      tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));

  Future<void> waitForReels(WidgetTester tester) async {
    for (var i = 0; i < 25 && find.byType(PageView).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
    }
    await settle(tester);
  }

  PostCard activeCard(WidgetTester tester) => tester.widgetList<PostCard>(find.byType(PostCard)).firstWhere((p) => p.active);

  testWidgets('a saved reel opens over the Notebook; back returns, and your place in the book stays', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('reel_peek');
    dirs.add(dir);
    late ProviderContainer c;
    late String bookId;
    late String savedSid;
    await tester.runAsync(() async {
      c = ProviderContainer(overrides: [storeProvider.overrideWithValue(await JsonStore.open(dir))]);
      c.read(settingsProvider.notifier).update((s) => s.copyWith(
          onboardingDone: true, goalSetupDone: true, gestureTutorialSeen: true, animatedBackground: false, cardLength: CardLength.standard));
      bookId = (await c.read(libraryProvider.notifier).ensureStarterBook())!.id;
      final seg = await c.read(segmentsProvider((bookId: bookId, length: CardLength.standard)).future);
      savedSid = seg[4]!.cards[3].startSid;
    });
    addTearDown(c.dispose);
    // (Before the providers go, even if the test fails midway.)
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    final router = c.read(routerProvider);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp.router(theme: buildAppTheme(Kit.appLight), routerConfig: router),
    ));
    await waitForReels(tester);

    // Reading: a few reels in, the place is saved.
    for (var i = 0; i < 3; i++) {
      await tester.fling(find.byType(PageView), const Offset(0, -500), 1500);
      await settle(tester);
    }
    final place = c.read(libraryProvider).single;
    expect(place.positionSid, isNotNull);
    final readingCard = activeCard(tester).card.startSid;

    // A card saved further on, opened from the Notebook.
    c.read(notebookProvider.notifier).toggleSaved(SavedCard(
          id: 'far',
          bookId: bookId,
          bookTitle: 'Alice',
          author: 'Lewis Carroll',
          chapterTitle: 'Chapter IV',
          startSid: savedSid,
          text: 'A card saved for later',
          createdAt: DateTime(2026, 11, 1),
        ));
    router.go('/notebook');
    await settle(tester);
    expect(find.byType(NotebookScreen), findsOneWidget);
    await tester.tap(find.text('A card saved for later').first);
    await waitForReels(tester);

    // Over the Notebook: the saved reel, with the way back.
    final look = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
    expect((look.peek, look.startSid, look.peekLabel), (true, savedSid, 'Saved'));
    expect(activeCard(tester).card.startSid, savedSid);
    expect(activeCard(tester).saved, isTrue);
    expect(find.byType(HomeShell), findsNothing, reason: 'no tab bar over a saved reel');
    expect(find.bySemanticsLabel('Back'), findsOneWidget);

    // Reading on from it moves nothing in the book.
    double page() => tester.widget<PageView>(find.byType(PageView)).controller!.page!;
    final first = page();
    for (var i = 0; i < 2; i++) {
      await tester.fling(find.byType(PageView), const Offset(0, -500), 1500);
      await settle(tester);
    }
    expect(page(), first + 2);
    final after = c.read(libraryProvider).single;
    expect((after.positionSid, after.lastReadAt, after.progress), (place.positionSid, place.lastReadAt, place.progress));

    // Back: the Notebook, then the book, still on the reel you were reading.
    expect(await tester.binding.handlePopRoute(), isTrue);
    await settle(tester);
    expect(find.byType(NotebookScreen), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is ReaderScreen && w.peek), findsNothing);
    expect(await tester.binding.handlePopRoute(), isTrue, reason: 'back from a tab goes to Reading, not out of the app');
    await settle(tester);
    final reader = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
    expect(reader.peek, isFalse);
    expect(activeCard(tester).card.startSid, readingCard);
    expect(c.read(libraryProvider).single.positionSid, place.positionSid);
    expect(c.read(musicProvider).track, isNotNull, reason: 'the book has its music back');

    // "Continue reading" in the Journal opens the same reel.
    router.go('/journal');
    await settle(tester);
    await tester.tap(find.text('Continue reading'));
    await waitForReels(tester);
    expect(activeCard(tester).card.startSid, readingCard);

    // From Reading, back leaves the app.
    expect(await tester.binding.handlePopRoute(), isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a liked quote from a book no longer in the Library says so', (tester) async {
    final dir = Directory.systemTemp.createTempSync('reel_peek');
    dirs.add(dir);
    late ProviderContainer c;
    await tester.runAsync(() async {
      c = ProviderContainer(overrides: [storeProvider.overrideWithValue(await JsonStore.open(dir))]);
      c.read(settingsProvider.notifier).update((s) => s.copyWith(onboardingDone: true));
    });
    addTearDown(c.dispose);
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => openReel(context, bookId: 'gone', sid: 'c0.b0.s0', from: 'liked'),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      GoRoute(path: '/reel/:bookId', builder: (context, _) => const Text('a reel')),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp.router(theme: buildAppTheme(Kit.appLight), routerConfig: router),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
    expect(find.text('That book isn’t in your Library any more'), findsOneWidget);
    expect(find.text('a reel'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpWidget(const SizedBox());
  });
}
