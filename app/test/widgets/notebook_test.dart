import 'dart:io';

import 'package:book_reel/data/json_store.dart';
import 'package:book_reel/data/notebook.dart';
import 'package:book_reel/data/store_provider.dart';
import 'package:book_reel/features/notebook/notebook_screen.dart';
import 'package:book_reel/ui/kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('All shows every note, newest first, each kind on its own very light shade', (tester) async {
    tester.view.physicalSize = const Size(1236, 2745);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('notebook');
    late ProviderContainer c;
    await tester.runAsync(() async {
      final store = await JsonStore.open(dir);
      c = ProviderContainer(overrides: [storeProvider.overrideWithValue(store)]);
      final n = c.read(notebookProvider.notifier);
      Future<void> later() => Future<void>.delayed(const Duration(milliseconds: 5));
      n.toggleSaved(SavedCard(
        id: n.newId(),
        bookId: 'b',
        bookTitle: 'Walden',
        author: 'Henry David Thoreau',
        chapterTitle: 'Economy',
        startSid: 'c0.b0.s0',
        text: 'Most of the luxuries are not only not indispensable.',
        createdAt: DateTime.now(),
      ));
      await later();
      n.addHighlight(bookId: 'b', bookTitle: 'Walden', sid: 'c0.b1.s0', text: 'Simplify, simplify.');
      await later();
      n.addWord(word: 'sanguine', meaning: 'hopeful', sentence: 'She was sanguine.', bookTitle: 'Emma');
      await later();
      n.addReflection(bookTitle: 'Walden', chapterTitle: 'Economy', text: 'Own less, live more.');
    });
    addTearDown(() {
      c.dispose();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(theme: buildAppTheme(Kit.appLight), home: const NotebookScreen()),
    ));
    await tester.pumpAndSettle();

    // All is the first choice, and open: every kind, newest first.
    expect(find.text('All 4'), findsOneWidget);
    final kinds = ['REFLECTION', 'WORD', 'HIGHLIGHT', 'SAVED'];
    final tops = [for (final k in kinds) tester.getTopLeft(find.text(k)).dy];
    expect(tops, [...tops]..sort(), reason: 'newest first');
    expect(find.text('Own less, live more.'), findsOneWidget);
    expect(find.text('sanguine'), findsOneWidget);
    expect(find.text('hopeful'), findsOneWidget);
    expect(find.text('Simplify, simplify.'), findsOneWidget);

    // Each on its own shade: all different, all very light.
    final shades = [
      for (final k in kinds)
        tester.widget<KitPanel>(find.ancestor(of: find.text(k), matching: find.byType(KitPanel)).first).color!,
    ];
    expect(shades.toSet(), hasLength(4));
    for (final s in shades) {
      expect(s.computeLuminance(), greaterThan(0.82), reason: 'a very light shade: $s');
    }

    // A kind on its own, with a tap you can feel.
    final played = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') played.add('${call.arguments}');
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    // (The kinds scroll along in a row.)
    await tester.drag(find.text('Highlights 1'), const Offset(-240, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Words 1'));
    await tester.pumpAndSettle();
    expect(find.text('REFLECTION'), findsNothing);
    expect(find.text('sanguine'), findsOneWidget);
    expect(played, ['HapticFeedbackType.lightImpact']);
  });
}
