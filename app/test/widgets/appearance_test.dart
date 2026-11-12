import 'dart:io';

import 'package:book_reel/app.dart';
import 'package:book_reel/core/segmentation/rule_segmenter.dart';
import 'package:book_reel/data/json_store.dart';
import 'package:book_reel/data/library.dart';
import 'package:book_reel/data/settings.dart';
import 'package:book_reel/data/settings_provider.dart';
import 'package:book_reel/data/store_provider.dart';
import 'package:book_reel/features/onboarding/onboarding_screen.dart';
import 'package:book_reel/features/reader/reader_screen.dart';
import 'package:book_reel/features/settings/settings_screen.dart';
import 'package:book_reel/features/shell/home_shell.dart';
import 'package:book_reel/services/scene_sound.dart';
import 'package:book_reel/ui/kit.dart';
import 'package:book_reel/ui/scenes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'reader_test.dart' show SilentLoop;

void main() {
  late Directory dir;
  late JsonStore store;
  late ProviderContainer c;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('appearance');
    store = await JsonStore.open(dir);
    c = ProviderContainer(overrides: [storeProvider.overrideWithValue(store)]);
    c.read(settingsProvider.notifier).update((s) => s.copyWith(onboardingDone: true, goalSetupDone: true, animatedBackground: false));
    await store.flush(); // before the test body: writes from setUp must not outlive the folder
    SceneSoundController.playerFactory = () => SilentLoop([]);
    SceneSoundController.fade = Duration.zero;
  });

  // No store.flush(): a write started inside a widget test's fake-async zone
  // never finishes once the test body ends (as in the other widget tests).
  tearDown(() {
    c.dispose();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  void tallScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1236, 2745);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  testWidgets('Settings → Appearance: system default, light or dark for every screen but the reader', (tester) async {
    tallScreen(tester);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final router = GoRouter(initialLocation: '/settings', routes: [
      GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
    ]);
    final app = ProviderContainer(overrides: [storeProvider.overrideWithValue(store), routerProvider.overrideWithValue(router)]);
    addTearDown(app.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: app, child: const BookReelApp()));
    await tester.pumpAndSettle();
    Kit kitOnScreen() => Kit.of(tester.element(find.text('Appearance')));
    expect(kitOnScreen(), same(Kit.appLight));
    expect(find.text('System default'), findsOneWidget, reason: 'the row shows the current choice');
    expect(find.byType(VibeBackground), findsNothing, reason: 'no scene outside the reader');

    // System default follows the phone.
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(kitOnScreen(), same(Kit.appDark));

    // Choose Light: light even when the phone is dark. The sheet closes.
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    expect(find.text('Follow the phone’s light or dark mode'), findsOneWidget);
    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(app.read(settingsProvider).appearance, AppAppearance.light);
    expect(find.text('Follow the phone’s light or dark mode'), findsNothing);
    expect(kitOnScreen(), same(Kit.appLight));

    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(kitOnScreen(), same(Kit.appDark));
    expect(Theme.of(tester.element(find.text('Appearance'))).brightness, Brightness.dark);
  });

  testWidgets('the tab shell and onboarding wear the app theme; scenes stay in the reader', (tester) async {
    tallScreen(tester);
    final router = GoRouter(initialLocation: '/a', routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => HomeShell(shell: shell),
        branches: [
          for (final p in ['/a', '/b', '/c', '/d'])
            StatefulShellBranch(routes: [GoRoute(path: p, builder: (context, state) => Text('page $p'))]),
        ],
      ),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp.router(theme: buildAppTheme(Kit.appDark), routerConfig: router),
    ));
    await tester.pumpAndSettle();
    expect(find.text('page /a'), findsOneWidget);
    expect(find.byType(VibeBackground), findsNothing);
    final shell = tester.widget<Scaffold>(find.descendant(of: find.byType(HomeShell), matching: find.byType(Scaffold)).first);
    expect(shell.backgroundColor, Kit.appDark.base);

    // Onboarding: plain dark page; the vibe step shows the scene in a small window.
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(theme: buildAppTheme(Kit.appDark), home: const OnboardingScreen()),
    ));
    await tester.pumpAndSettle();
    final title = tester.widget<Text>(find.text('Scroll books\nlike reels.'));
    expect(title.style?.color, Kit.appDark.ink);
    expect(find.byType(VibeBackground), findsNothing);
    await tester.tap(find.text('Get started'));
    // The preview scene moves (it never settles): pump past the transition.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Pick your study vibe'), findsOneWidget);
    // Only small windows onto scenes: the 190 px preview and the picker's thumbnails.
    final heights = [for (final e in find.byType(VibeBackground).evaluate()) (e.renderObject! as RenderBox).size.height];
    expect(heights, contains(190));
    expect(heights.every((h) => h <= 190), isTrue, reason: 'no full-screen scene outside the reader');
  });

  testWidgets('the reader keeps its scene even when the app is dark', (tester) async {
    late String bookId;
    await tester.runAsync(() async {
      c.read(settingsProvider.notifier).update((s) => s.copyWith(gestureTutorialSeen: true, vibe: Vibe.meadow, cardLength: CardLength.standard));
      bookId = (await c.read(libraryProvider.notifier).ensureStarterBook())!.id;
    });
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(theme: buildAppTheme(Kit.appDark), home: ReaderScreen(bookId: bookId)),
    ));
    for (var i = 0; i < 20 && find.text('Swipe up to begin').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
    }
    expect(find.byType(VibeBackground), findsWidgets);
    final kit = Kit.of(tester.element(find.text('Swipe up to begin')));
    expect(kit.vibe, Vibe.meadow);
    expect(kit.palette, isNotNull, reason: 'sheets opened here wear the scene, not the app’s dark theme');
    expect(kit.dark, isFalse, reason: 'meadow is a daylight scene');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
