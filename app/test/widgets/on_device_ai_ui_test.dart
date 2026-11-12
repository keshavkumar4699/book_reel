import 'dart:async';
import 'dart:io';

import 'package:book_reel/core/text/lexicon.dart';
import 'package:book_reel/data/json_store.dart';
import 'package:book_reel/data/notebook.dart';
import 'package:book_reel/data/settings.dart';
import 'package:book_reel/data/settings_provider.dart';
import 'package:book_reel/data/store_provider.dart';
import 'package:book_reel/features/reader/word_sheet.dart';
import 'package:book_reel/features/settings/settings_screen.dart';
import 'package:book_reel/services/on_device_ai.dart';
import 'package:book_reel/ui/kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../services/on_device_ai_test.dart' show FakeProbe, FakeRuntime, gb;

void main() {
  late Directory dir;
  late JsonStore store;
  late ProviderContainer c;
  late FakeRuntime runtime;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('ondevice_ui');
    store = await JsonStore.open(dir);
    runtime = FakeRuntime();
    OnDeviceAiController.runtimeFactory = () => runtime;
    OnDeviceAiController.probeFactory = () => FakeProbe(const DeviceProfile(supported: true, totalRamBytes: 6 * gb, freeBytes: 20 * gb));
    c = ProviderContainer(overrides: [storeProvider.overrideWithValue(store)]);
  });

  // No store.flush(): a write started inside a widget test's fake-async zone
  // never finishes once the test body ends (as in the other widget tests).
  tearDown(() {
    c.dispose();
    OnDeviceAiController.runtimeFactory = () => null;
    OnDeviceAiController.probeFactory = PlatformDeviceProbe.new;
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  testWidgets('Free plan: download the on-device model in Settings, then pause it; paid plans don’t show it', (tester) async {
    tester.view.physicalSize = const Size(1236, 2745);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final router = GoRouter(initialLocation: '/settings', routes: [
      GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp.router(theme: buildAppTheme(Kit.appLight), routerConfig: router),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('On-device AI'));
    await tester.pumpAndSettle();
    expect(find.textContaining('your books never leave your phone'), findsOneWidget);
    expect(find.text('Qwen3 0.6B'), findsOneWidget);
    // 6 GB of memory: the 2 GB model is offered but can't be picked.
    expect(find.textContaining('Needs a phone with 8 GB of memory'), findsOneWidget);

    await tester.tap(find.text('Download · 345 MB'));
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).localModel, 'qwen3-0.6b');
    expect(find.text('Use on-device AI'), findsOneWidget);
    expect(find.text('Remove model (frees 345 MB)'), findsOneWidget);
    await tester.tap(find.text('Use on-device AI'));
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).onDeviceAi, isFalse);
    expect(c.read(onDeviceAiProvider.notifier).usable, isFalse);

    // Close the sheet; the row shows the state. Paid plans have no row.
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.text('Paused'), findsOneWidget);
    c.read(settingsProvider.notifier).update((s) => s.copyWith(tier: Tier.plus));
    await tester.pumpAndSettle();
    expect(find.text('On-device AI'), findsNothing);
  });

  testWidgets('word sheet: the on-device model explains a word in its sentence, and the word list keeps it', (tester) async {
    final answer = Completer<String?>();
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: buildAppTheme(Kit.appLight),
        home: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showWordSheet(context,
                  word: 'sanguine',
                  sentence: 'He was sanguine about the plan.',
                  bookTitle: 'A Book',
                  lexicon: Lexicon.empty,
                  onDeviceMeaning: () => answer.future),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('Working out what it means here'), findsOneWidget);
    answer.complete('Hopeful and confident');
    await tester.pumpAndSettle();
    expect(find.text('IN THIS SENTENCE · ON-DEVICE AI'), findsOneWidget);
    expect(find.text('Hopeful and confident'), findsOneWidget);
    await tester.tap(find.text('Add to word list'));
    await tester.pumpAndSettle();
    expect(c.read(notebookProvider).words.single.meaning, 'Hopeful and confident');
  });
}
