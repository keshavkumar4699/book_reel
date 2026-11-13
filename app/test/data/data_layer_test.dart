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
import 'package:book_reel/core/models/book.dart';
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

  test('highlights cover a range of words, possibly over several sentences', () {
    final at = DateTime(2026, 11, 12);
    // "quiet power" inside c0.b1.s2, and from c0.b1.s2[10] to c0.b2.s0[5].
    final word = Highlight(id: 'w', bookId: 'b', bookTitle: 'B', sid: 'c0.b1.s2', start: 4, end: 15, text: 'quiet power', createdAt: at);
    final span = Highlight(id: 's', bookId: 'b', bookTitle: 'B', sid: 'c0.b1.s2', endSid: 'c0.b2.s0', start: 10, end: 5, text: '…', createdAt: at);
    final whole = Highlight(id: 'h', bookId: 'b', bookTitle: 'B', sid: 'c0.b1.s2', text: 'All of it.', createdAt: at);
    expect(word.spanIn('c0.b1.s2', 40), (from: 4, to: 15));
    expect(word.spanIn('c0.b1.s3', 40), isNull);
    expect(span.spanIn('c0.b1.s2', 40), (from: 10, to: 40));
    expect(span.spanIn('c0.b1.s9', 30), (from: 0, to: 30), reason: 'sentences in between are covered whole');
    expect(span.spanIn('c0.b2.s0', 30), (from: 0, to: 5));
    expect(span.spanIn('c0.b2.s1', 30), isNull);
    expect(whole.spanIn('c0.b1.s2', 12), (from: 0, to: 12), reason: 'older highlights cover their whole sentence');
    // Order is by chapter, then block, then sentence (not string order).
    expect(compareSids('c0.b2.s0', 'c0.b10.s0'), lessThan(0));
    // Ranges survive storage and sync.
    final back = Highlight.fromJson(span.toJson());
    expect((back.sid, back.endSid, back.start, back.end), ('c0.b1.s2', 'c0.b2.s0', 10, 5));
    expect(Highlight.fromJson(whole.toJson()).start, isNull);
    expect(whole.toJson().containsKey('end_sid'), isFalse);
  });

  test('adjusted highlights are saved over the ones they absorbed', () {
    final n = container.read(notebookProvider.notifier);
    final a = n.addHighlight(bookId: 'b', bookTitle: 'Book', sid: 'c0.b0.s0', text: 'First.');
    final b = n.addHighlight(bookId: 'b', bookTitle: 'Book', sid: 'c0.b0.s1', text: 'Second.');
    expect(container.read(notebookProvider).highlightsIn('b', 'c0.b0.s1').map((h) => h.id), [b.id]);
    final merged = a.withRange(sid: 'c0.b0.s0', endSid: 'c0.b0.s1', start: 0, end: 7, text: 'First. Second.');
    n.saveHighlight(merged, absorbed: {b.id});
    final all = container.read(notebookProvider).highlights;
    expect(all.map((h) => h.id), [a.id]);
    expect((all.single.endSid, all.single.text), ('c0.b0.s1', 'First. Second.'));
    expect(container.read(notebookProvider).highlightsIn('b', 'c0.b0.s1').single.id, a.id);
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

  test('every saved document comes back after a restart (mood and sessions included)', () async {
    final dir = Directory.systemTemp.createTempSync('store_reopen');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = await JsonStore.open(dir);
    for (final name in ['settings', 'mood', 'sessions', 'some_future_doc']) {
      await store.saveDoc(name, {'name': name});
    }
    await store.flush();
    File('${dir.path}/half.json.tmp').writeAsStringSync('{"broken"');
    File('${dir.path}/corrupt.json').writeAsStringSync('{"broken"');

    final again = await JsonStore.open(dir);
    for (final name in ['settings', 'mood', 'sessions', 'some_future_doc']) {
      expect(again.doc(name), {'name': name}, reason: name);
    }
    expect(again.doc('half'), isNull, reason: 'a half-written file is ignored');
    expect(again.doc('corrupt'), isNull, reason: 'a corrupt file starts fresh');
  });
}
