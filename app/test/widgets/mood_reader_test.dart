import 'dart:io';

import 'package:book_reel/data/api_client.dart';
import 'package:book_reel/data/json_store.dart';
import 'package:book_reel/data/library.dart';
import 'package:book_reel/data/settings.dart';
import 'package:book_reel/data/settings_provider.dart';
import 'package:book_reel/data/store_provider.dart';
import 'package:book_reel/features/reader/reader_screen.dart';
import 'package:book_reel/services/mood.dart';
import 'package:book_reel/services/scene_sound.dart';
import 'package:book_reel/ui/kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../services/mood_test.dart' show FakeMoodApi;
import 'reader_test.dart' show SilentLoop;

void main() {
  final stores = <String, (ProviderContainer, JsonStore)>{};
  // Stores finish writing in the background: their folders go at the end.
  final dirs = <Directory>[];
  tearDownAll(() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final d in dirs) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
  });
  setUp(() {
    SceneSoundController.playerFactory = () => SilentLoop([]);
    SceneSoundController.fade = Duration.zero;
  });

  /// The Reading tab's reader on the starter book, at [now].
  Future<(ProviderContainer, Directory)> open(WidgetTester tester, DateTime now, {BookReelApi? api, void Function(ProviderContainer c)? before}) async {
    final dir = Directory.systemTemp.createTempSync('mood_reader');
    dirs.add(dir);
    late ProviderContainer c;
    late String bookId;
    late JsonStore store;
    await tester.runAsync(() async {
      store = await JsonStore.open(dir);
      c = ProviderContainer(overrides: [
        storeProvider.overrideWithValue(store),
        apiProvider.overrideWithValue(api ?? FakeMoodApi(null, online: false)),
      ]);
      c.read(settingsProvider.notifier).update((s) => s.copyWith(
          onboardingDone: true, goalSetupDone: true, gestureTutorialSeen: true, animatedBackground: false, vibe: Vibe.paper));
      c.read(moodProvider.notifier).clock = () => now;
      before?.call(c);
      bookId = (await c.read(libraryProvider.notifier).ensureStarterBook())!.id;
    });
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(theme: buildAppTheme(Kit.appLight), home: ReaderScreen(bookId: bookId, embedded: true)),
    ));
    for (var i = 0; i < 20 && find.text('Swipe up to begin').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
    }
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
    stores[dir.path] = (c, store);
    return (c, dir);
  }

  Future<void> close(WidgetTester tester, Directory dir) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 6));
    stores.remove(dir.path)!.$1.dispose();
  }

  testWidgets('while learning, opening a book asks how you feel and sets the scene', (tester) async {
    final (c, dir) = await open(tester, DateTime(2026, 11, 10, 21));
    expect(find.text('How are you feeling?'), findsOneWidget);
    for (final m in Mood.values) {
      expect(find.text(m.label), findsOneWidget, reason: m.label);
    }
    await tester.tap(find.text('Cozy'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
    expect(find.text('How are you feeling?'), findsNothing);
    expect(c.read(settingsProvider).vibe, Vibe.cafe, reason: 'cozy, in the evening');
    expect(c.read(moodProvider).log.single.source, MoodSource.asked);
    await close(tester, dir);
  });

  testWidgets('"Not now" or "Never": the book just opens', (tester) async {
    final (c, dir) = await open(tester, DateTime(2026, 11, 10, 21));
    await tester.ensureVisible(find.text('Not now')); // the sheet scrolls on short screens
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
    expect(c.read(moodProvider).log, isEmpty);
    expect(c.read(moodProvider).lastAsked, isNotNull);
    expect(c.read(settingsProvider).vibe, Vibe.paper);
    await close(tester, dir);

    final (_, dir2) = await open(tester, DateTime(2026, 11, 10, 21), before: (c) => c.read(settingsProvider.notifier).update((s) => s.copyWith(moodAsk: MoodAsk.never)));
    expect(find.text('How are you feeling?'), findsNothing);
    await close(tester, dir2);
  });

  testWidgets('once learnt, Gemma picks the mood; the chip corrects it', (tester) async {
    final now = DateTime(2026, 11, 20, 21);
    final api = FakeMoodApi((mood: 'dreamy', reason: 'Late reads drift.'));
    final (c, dir) = await open(tester, now, api: api, before: (c) {
      final mood = c.read(moodProvider.notifier);
      for (var i = 15; i >= 1; i--) {
        mood.clock = () => DateTime(now.year, now.month, now.day - i, 21);
        mood.answer(Mood.cozy);
      }
      mood.clock = () => now;
    });
    expect(find.text('How are you feeling?'), findsNothing, reason: 'past learning: no asking until the weekly check-in');
    expect(api.logs, hasLength(1));
    expect(c.read(settingsProvider).vibe, Vibe.night, reason: 'dreamy, at night');
    expect(find.bySemanticsLabel('Mood: Dreamy. Change'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Mood: Dreamy. Change'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
    expect(find.text('How are you feeling?'), findsOneWidget);
    await tester.ensureVisible(find.text('Restless'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restless'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
    expect(c.read(moodProvider).log.last.source, MoodSource.corrected);
    expect(c.read(moodProvider).current, Mood.restless);
    expect(c.read(settingsProvider).vibe, Vibe.city);

    // The chip fades after a few seconds.
    await tester.pump(const Duration(seconds: 6));
    expect(tester.widget<AnimatedOpacity>(find.ancestor(of: find.textContaining('change'), matching: find.byType(AnimatedOpacity))).opacity, 0);
    await close(tester, dir);
  });
}
