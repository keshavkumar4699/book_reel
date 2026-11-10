import 'dart:io';

import 'package:book_reel/core/models/reel_card.dart';
import 'package:book_reel/core/segmentation/rule_segmenter.dart';
import 'package:book_reel/data/habit.dart';
import 'package:book_reel/data/json_store.dart';
import 'package:book_reel/data/library.dart';
import 'package:book_reel/data/notebook.dart';
import 'package:book_reel/data/segments.dart';
import 'package:book_reel/data/settings_provider.dart';
import 'package:book_reel/data/store_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late JsonStore store;
  late ProviderContainer container;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('bookreel_test');
    store = await JsonStore.open(dir);
    container = ProviderContainer(overrides: [storeProvider.overrideWithValue(store)]);
  });

  tearDown(() async {
    container.dispose();
    await store.flush();
    await dir.delete(recursive: true);
  });

  test('imports the starter book once, parses and segments it', () async {
    final library = container.read(libraryProvider.notifier);
    final meta = await library.ensureStarterBook();
    expect(meta, isNotNull);
    expect(meta!.title, "Alice's Adventures in Wonderland");
    expect(meta.isPublicDomain, isTrue);
    expect(await library.ensureStarterBook(), isNull, reason: 'starter is imported only once');
    expect(container.read(libraryProvider), hasLength(1));

    final segments = await container.read(segmentsProvider((bookId: meta.id, length: CardLength.standard)).future);
    expect(segments, hasLength(11));
    expect(segments.values.every((s) => s.source == SegmentSource.rules), isTrue);
    expect(File(store.blobPath('${meta.id}.rules.standard.json')).existsSync(), isTrue);
  });

  test('re-importing the same file returns the existing entry', () async {
    final bytes = File('assets/books/alice.epub').readAsBytesSync();
    final library = container.read(libraryProvider.notifier);
    final a = await library.importBytes(bytes, 'a.epub');
    final b = await library.importBytes(bytes, 'copy.epub');
    expect(a.id, b.id);
    expect(container.read(libraryProvider), hasLength(1));
  });

  test('reading position and progress persist across restarts', () async {
    final library = container.read(libraryProvider.notifier);
    final meta = (await library.ensureStarterBook())!;
    final content = await container.read(bookContentProvider(meta.id).future);
    final sid = content.chapters[5].blocks[0].sentences[0].id;
    library.updatePosition(meta.id, sid: sid, offset: 187, progress: progressAt(content, sid));
    await store.flush();

    final store2 = await JsonStore.open(dir);
    final reopened = ProviderContainer(overrides: [storeProvider.overrideWithValue(store2)]);
    final again = reopened.read(libraryProvider).single;
    expect(again.positionSid, sid);
    // Part-way through a long sentence that continues over several reels.
    expect(again.positionOffset, 187);
    expect(again.progress, greaterThan(0.3));
    expect(again.progress, lessThan(0.7));
    // The book's fonts chosen on import survive too.
    expect(again.voice, meta.voice);
    expect(again.voiceSource, 'rules');
    // Moving on to the start of a sentence clears the offset.
    reopened.read(libraryProvider.notifier).updatePosition(meta.id, sid: sid, progress: 0.5);
    expect(reopened.read(libraryProvider).single.positionOffset, 0);
    reopened.dispose();
    await store2.flush();
  });

  test('habit: verified cards complete the goal once and start a streak', () {
    container.read(settingsProvider.notifier).update((s) => s.copyWith(dailyGoal: 3));
    final habit = container.read(habitProvider.notifier);
    habit.clock = () => DateTime(2026, 11, 9, 9);
    expect(habit.recordCard(words: 120, dwellMs: 2000).verified, isFalse, reason: 'skimmed');
    habit.recordCard(words: 120, dwellMs: 30000);
    habit.recordCard(words: 120, dwellMs: 30000);
    final third = habit.recordCard(words: 120, dwellMs: 30000);
    expect(third.goalJustMet, isTrue);
    expect(third.streak, 1);
    expect(habit.recordCard(words: 120, dwellMs: 30000).goalJustMet, isFalse);
    final today = container.read(habitProvider).today(DateTime(2026, 11, 9));
    expect(today.verifiedCards, 4);
    expect(today.skimmedCards, 1);
  });

  test('notebook: highlights, saves, words and markdown export', () {
    final n = container.read(notebookProvider.notifier);
    final h = n.toggleHighlight(bookId: 'b', bookTitle: 'Book', sid: 'c0.b0.s0', text: 'A key idea.');
    expect(h, isNotNull);
    n.updateHighlight(h!.copyWith(note: 'Use this at work'));
    n.toggleSaved(SavedCard(
      id: '1', bookId: 'b', bookTitle: 'Book', author: 'A', chapterTitle: 'One', startSid: 'c0.b0.s0',
      text: 'Card text', createdAt: DateTime(2026),
    ));
    n.addWord(word: 'sanguine', meaning: 'optimistic', sentence: 'She was sanguine.', bookTitle: 'Book');
    n.addReflection(bookTitle: 'Book', chapterTitle: 'One', text: 'Start small.');
    final state = container.read(notebookProvider);
    expect(state.isSaved('b', 'c0.b0.s0'), isTrue);
    expect(state.hasWord('Sanguine'), isTrue);
    final md = notebookToMarkdown(state);
    expect(md, contains('> A key idea.'));
    expect(md, contains('Use this at work'));
    expect(md, contains('**sanguine**: optimistic'));
    expect(md, contains('Start small.'));
    expect(n.toggleHighlight(bookId: 'b', bookTitle: 'Book', sid: 'c0.b0.s0', text: 'A key idea.'), isNull);
  });

  test('word review moves words through spaced intervals', () {
    final now = DateTime(2026, 11, 9);
    var w = WordEntry(word: 'x', meaning: 'm', sentence: '', bookTitle: '', addedAt: now, dueAt: now);
    w = w.reviewed(remembered: true, now: now);
    expect(w.dueAt, now.add(const Duration(days: 3)));
    w = w.reviewed(remembered: false, now: now);
    expect(w.box, 0);
    expect(w.dueAt, now.add(const Duration(days: 1)));
  });
}
