import 'dart:io';

import 'package:book_reel/core/segmentation/rule_segmenter.dart';
import 'package:book_reel/data/habit.dart';
import 'package:book_reel/data/json_store.dart';
import 'package:book_reel/data/library.dart';
import 'package:book_reel/data/segments.dart';
import 'package:book_reel/data/settings.dart';
import 'package:book_reel/data/settings_provider.dart';
import 'package:book_reel/data/store_provider.dart';
import 'package:book_reel/features/reader/cards/text_card.dart';
import 'package:book_reel/features/reader/reader_screen.dart';
import 'package:book_reel/services/scene_sound.dart';
import 'package:book_reel/ui/kit.dart';
import 'package:book_reel/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'reader_test.dart' show SilentLoop;

/// Swiping, saving and celebrating in the reader: nothing is written while a
/// reel moves, a rebuilt feed keeps the reel on screen, and meeting the goal
/// never stops the reading.
void main() {
  final dirs = <Directory>[];
  setUp(() {
    SceneSoundController.playerFactory = () => SilentLoop([]);
    SceneSoundController.fade = Duration.zero;
  });
  tearDown(() => ReaderScreen.clock = DateTime.now);
  tearDownAll(() async {
    // Writes from the last test can still be landing: wait, then clean up.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final d in dirs) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
  });

  Future<(ProviderContainer, String)> open(WidgetTester tester, {AppSettings Function(AppSettings)? settings, String? Function(ProviderContainer, String)? startAt}) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('reader_flow');
    dirs.add(dir);
    late ProviderContainer container;
    late String bookId;
    String? start;
    await tester.runAsync(() async {
      container = ProviderContainer(overrides: [storeProvider.overrideWithValue(await JsonStore.open(dir))]);
      container.read(settingsProvider.notifier).update((s) {
        final base = s.copyWith(
            onboardingDone: true, goalSetupDone: true, gestureTutorialSeen: true, animatedBackground: false, cardLength: CardLength.standard);
        return settings == null ? base : settings(base);
      });
      bookId = (await container.read(libraryProvider.notifier).ensureStarterBook())!.id;
      if (startAt != null) {
        await container.read(segmentsProvider((bookId: bookId, length: CardLength.standard)).future);
        start = startAt(container, bookId);
      }
    });
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildAppTheme(Kit.forScene(Vibe.forest, ReadingTheme.of(ReadingThemeId.paper))),
        home: ReaderScreen(bookId: bookId, startSid: start),
      ),
    ));
    for (var i = 0; i < 25 && find.byType(PageView).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
    }
    await tester.pump();
    return (container, bookId);
  }

  Future<void> settle(WidgetTester tester) =>
      tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));

  testWidgets('reading time counts once the reel comes to rest; the goal met is a toast, not a stop', (tester) async {
    var now = DateTime(2026, 11, 17, 9);
    ReaderScreen.clock = () => now;
    final (c, bookId) = await open(tester, settings: (s) => s.copyWith(dailyGoal: 1));
    int verified() => c.read(habitProvider).totalVerifiedCards;
    await tester.fling(find.byType(PageView), const Offset(0, -500), 1500); // past the chapter card
    await settle(tester);

    // A minute on each reel, until a whole card has been read.
    for (var i = 0; i < 8 && verified() == 0; i++) {
      now = now.add(const Duration(minutes: 1));
      final g = await tester.startGesture(const Offset(180, 420));
      await g.moveBy(const Offset(0, -40));
      await tester.pump();
      await g.moveBy(const Offset(0, -420)); // past halfway: the next reel is the page now
      await tester.pump();
      expect(verified(), 0, reason: 'nothing is written while the reel moves');
      await g.up();
      await settle(tester);
    }
    expect(verified(), 1);
    expect(c.read(libraryProvider).single.positionSid, isNotNull, reason: 'the place is saved too');

    // Goal met: a toast with the celebration a tap away, while the reels stay live.
    expect(find.text('Goal done · 1-day streak'), findsOneWidget);
    expect(find.text('See'), findsOneWidget);
    expect(find.text('Keep reading'), findsNothing, reason: 'no screen in the way');
    double page() => tester.widget<PageView>(find.byType(PageView)).controller!.page!;
    final before = page();
    now = now.add(const Duration(minutes: 1));
    await tester.fling(find.byType(PageView), const Offset(0, -500), 1500);
    await settle(tester);
    expect(page(), before + 1, reason: 'swiping goes on under the toast');
    await tester.pump(const Duration(seconds: 6));
    await settle(tester);
    expect(find.text('Goal done · 1-day streak'), findsNothing, reason: 'it leaves on its own');
  });

  testWidgets('a feed rebuilt under the reader keeps the same reel on screen', (tester) async {
    // Card 12 of chapter 1: past the quick check after card 10.
    final (c, _) = await open(tester, startAt: (c, id) {
      final seg = c.read(segmentsProvider((bookId: id, length: CardLength.standard))).value!;
      return seg[1]!.cards[12].startSid;
    });
    final before = tester.widget<PostCard>(find.byType(PostCard));
    final pager = tester.widget<PageView>(find.byType(PageView)).controller!;
    final pageBefore = pager.page;
    // Quick checks off: fewer cards before this one (in chapters 0 and 1).
    c.read(settingsProvider.notifier).update((s) => s.copyWith(recallCards: false));
    await tester.pump();
    await settle(tester);
    final after = tester.widget<PostCard>(find.byType(PostCard));
    expect(identical(after.card, before.card), isTrue, reason: 'the same card');
    expect(after.lines, before.lines, reason: 'and the same part of it');
    expect(tester.widget<PageView>(find.byType(PageView)).controller!.page, lessThan(pageBefore!), reason: 'its index moved; the reel did not');
    expect(after.animateIn, isFalse, reason: 'it was already on screen: no second fade-in');
  });
}
