import 'dart:io';

import 'package:book_reel/data/json_store.dart';
import 'package:book_reel/data/library.dart';
import 'package:book_reel/data/notebook.dart';
import 'package:book_reel/data/settings_provider.dart';
import 'package:book_reel/data/store_provider.dart';
import 'package:book_reel/features/journal/journal_screen.dart';
import 'package:book_reel/features/library/library_screen.dart';
import 'package:book_reel/features/notebook/notebook_screen.dart';
import 'package:book_reel/features/profile/profile_screen.dart';
import 'package:book_reel/features/settings/settings_screen.dart';
import 'package:book_reel/ui/kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Production plan B4: every main screen, light and dark, at the default
/// and at double text size: tap targets of at least 48 dp, every button
/// labelled for screen readers, text with enough contrast, and nothing
/// overflowing.
void main() {
  final dirs = <Directory>[];
  tearDownAll(() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final d in dirs) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
  });

  final screens = <String, Widget Function()>{
    'Journal': () => const JournalScreen(),
    'Library': () => const LibraryScreen(),
    'Notebook': () => const NotebookScreen(),
    'Profile': () => const ProfileScreen(),
    'Settings': () => const SettingsScreen(),
  };

  Future<void> open(WidgetTester tester, Widget screen, {required bool dark, double textScale = 1}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('a11y');
    dirs.add(dir);
    late ProviderContainer c;
    await tester.runAsync(() async {
      final store = await JsonStore.open(dir);
      c = ProviderContainer(overrides: [storeProvider.overrideWithValue(store)]);
      c.read(settingsProvider.notifier).update((s) => s.copyWith(onboardingDone: true, goalSetupDone: true, displayName: 'Asha'));
      final book = (await c.read(libraryProvider.notifier).ensureStarterBook())!;
      c.read(notebookProvider.notifier).addHighlight(bookId: book.id, bookTitle: book.title, sid: 'c0.b0.s0', text: 'Down the rabbit hole.');
    });
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: buildAppTheme(dark ? Kit.appDark : Kit.appLight),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          // The tab shell paints the page behind each tab.
          child: ColoredBox(color: (dark ? Kit.appDark : Kit.appLight).base, child: child),
        ),
        home: screen,
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  }

  for (final dark in [false, true]) {
    for (final e in screens.entries) {
      testWidgets('${e.key} (${dark ? 'dark' : 'light'}): tap targets, labels and contrast', (tester) async {
        final semantics = tester.ensureSemantics();
        await open(tester, e.value(), dark: dark);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        semantics.dispose();
      });
    }
  }

  for (final e in screens.entries) {
    testWidgets('${e.key} at double text size: nothing overflows', (tester) async {
      await open(tester, e.value(), dark: false, textScale: 2);
      // A layout overflow is reported as an exception, which fails the test.
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -1200));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    });
  }
}
