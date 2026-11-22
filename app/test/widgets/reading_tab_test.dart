import 'dart:io';

import 'package:book_reel/data/json_store.dart';
import 'package:book_reel/data/library.dart';
import 'package:book_reel/data/settings_provider.dart';
import 'package:book_reel/data/store_provider.dart';
import 'package:book_reel/features/reader/reader_screen.dart';
import 'package:book_reel/features/reader/reading_tab.dart';
import 'package:book_reel/ui/kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../silent_music.dart';

/// The Reading tab holds the book asked for, or the one read last when
/// that book isn't in the Library (removed, say).
void main() {
  final dirs = <Directory>[];
  setUp(quietReader);
  tearDownAll(() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final d in dirs) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
  });

  Future<ProviderContainer> container(WidgetTester tester, {bool withBook = true}) async {
    final dir = Directory.systemTemp.createTempSync('reading_tab');
    dirs.add(dir);
    late ProviderContainer c;
    await tester.runAsync(() async {
      c = ProviderContainer(overrides: [storeProvider.overrideWithValue(await JsonStore.open(dir))]);
      c.read(settingsProvider.notifier).update((s) => s.copyWith(onboardingDone: true, goalSetupDone: true, gestureTutorialSeen: true));
      if (withBook) await c.read(libraryProvider.notifier).ensureStarterBook();
    });
    addTearDown(c.dispose);
    return c;
  }

  Future<void> show(WidgetTester tester, ProviderContainer c, Widget tab) async {
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(theme: buildAppTheme(Kit.appLight), home: tab),
    ));
    await tester.pump();
  }

  testWidgets('a book that isn’t in the Library gives way to the one read last', (tester) async {
    final c = await container(tester);
    final book = c.read(libraryProvider).single;
    await show(tester, c, const ReadingTab(bookId: 'gone', startSid: 'c3.b0.s0'));
    final reader = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
    expect(reader.bookId, book.id);
    expect(reader.startSid, isNull, reason: 'a place in the missing book means nothing in this one');

    // Removing the book on screen leaves nothing to read.
    await tester.runAsync(() => c.read(libraryProvider.notifier).remove(book.id));
    await tester.pumpWidget(const SizedBox());
    await show(tester, c, ReadingTab(bookId: book.id));
    expect(find.byType(ReaderScreen), findsNothing);
    expect(find.text('Nothing to read yet'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
