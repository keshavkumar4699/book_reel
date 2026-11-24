import 'dart:io';

import 'package:book_reel/data/json_store.dart';
import 'package:book_reel/data/library.dart';
import 'package:book_reel/data/settings_provider.dart';
import 'package:book_reel/data/store_provider.dart';
import 'package:book_reel/features/library/library_screen.dart';
import 'package:book_reel/services/books_folder.dart';
import 'package:book_reel/ui/kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fake_books_folder.dart';

/// The Library and the books folder: a suggestion until one is chosen, then
/// a line saying where new books come from.
void main() {
  final dirs = <Directory>[];
  late FakeFolderPhone phone;
  late JsonStore store;
  tearDownAll(() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final d in dirs) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
  });

  List<String> titles(ProviderContainer c) => [for (final b in c.read(libraryProvider)) b.title]..sort();

  testWidgets('the Library suggests a folder until one is chosen, then says where books come from', (tester) async {
    final dir = Directory.systemTemp.createTempSync('library_folder');
    dirs.add(dir);
    phone = FakeFolderPhone(dir);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(BooksFolderNotifier.channel, phone.handle);
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(BooksFolderNotifier.channel, null));
    late ProviderContainer c;
    await tester.runAsync(() async {
      store = await JsonStore.open(dir);
      c = ProviderContainer(overrides: [storeProvider.overrideWithValue(store)]);
      c.read(settingsProvider.notifier).update((s) => s.copyWith(onboardingDone: true));
    });
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(theme: buildAppTheme(Kit.appLight), home: const LibraryScreen()),
    ));
    await tester.pump();
    expect(find.text('Import books automatically'), findsOneWidget);
    expect(find.bySemanticsLabel('Books folder'), findsOneWidget);

    // Put away, it stays away.
    await tester.tap(find.bySemanticsLabel('Not now'));
    await tester.pump();
    expect(find.text('Import books automatically'), findsNothing);
    expect(c.read(booksFolderProvider).hintHidden, isTrue);

    // Chosen (from the folder button): the Library says where books come from.
    phone.put('a', 'Morning.epub', epubNamed('Morning'));
    await tester.tap(find.bySemanticsLabel('Books folder'));
    await tester.pumpAndSettle();
    expect(find.text('Import books automatically'), findsOneWidget, reason: 'the sheet explains it first');
    await tester.tap(find.text('Choose folder'));
    for (var i = 0; i < 20 && c.read(libraryProvider).isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    await tester.pump();
    expect(titles(c), ['Morning']);
    expect(find.text('New books in Books appear here by themselves'), findsOneWidget);
    expect(find.text('Added 1 book from Books'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpWidget(const SizedBox());
  });
}
