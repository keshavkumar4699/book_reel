import 'dart:io';

import 'package:book_reel/core/models/book.dart';
import 'package:book_reel/core/models/reel_card.dart';
import 'package:book_reel/core/segmentation/feed_builder.dart';
import 'package:book_reel/core/segmentation/rule_segmenter.dart';
import 'package:book_reel/data/json_store.dart';
import 'package:book_reel/data/local_ai.dart';
import 'package:book_reel/data/settings_provider.dart';
import 'package:book_reel/data/store_provider.dart';
import 'package:book_reel/services/on_device_ai.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../services/on_device_ai_test.dart' show FakeProbe, FakeRuntime, ScriptedLlm, gb;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('checks on what the model writes', () {
    test('recap bullets: 2–3 plain lines, chatter dropped', () {
      expect(
        parseBullets('Here is a recap:\n- Alice follows the **White Rabbit** down a hole\n- She falls slowly past shelves of jars\n'
            '- She lands softly on a heap of dry leaves.\n- An extra fourth line that should not be kept here'),
        ['Alice follows the White Rabbit down a hole.', 'She falls slowly past shelves of jars.', 'She lands softly on a heap of dry leaves.'],
      );
      expect(parseBullets('1. Alice is bored by the river bank\n2) She sees a rabbit with a pocket watch'),
          ['Alice is bored by the river bank.', 'She sees a rabbit with a pocket watch.']);
      expect(parseBullets('<think>hmm</think>- Only one bullet survives here'), isNull);
      expect(parseBullets('Alice falls. She lands.'), isNull, reason: 'not bullets');
      expect(parseBullets('- A recap of the passage\n- Short'), isNull);
    });

    const key = 'The rabbit took a watch out of its waistcoat pocket and hurried on.';

    test('quick check: the right answer must come from the key sentence', () {
      const reply = 'Q: What did the rabbit take out of its pocket?\nA: A watch\nB: A key\nC: A letter';
      final q = parseQuickCheck(reply, key, seed: 0)!;
      expect(q.question, 'What did the rabbit take out of its pocket?');
      expect(q.options[q.answerIndex], 'A watch');
      final shifted = parseQuickCheck(reply, key, seed: 4)!;
      expect(shifted.answerIndex, 1);
      expect(shifted.options[shifted.answerIndex], 'A watch');
      expect(shifted.options.toSet(), {'A watch', 'A key', 'A letter'});

      // A made-up right answer, a question without "?", repeated options,
      // a "wrong" answer that is really right, and missing lines: all dropped.
      expect(parseQuickCheck('Q: What did the rabbit hold?\nA: A golden umbrella\nB: A key\nC: A hat', key), isNull);
      expect(parseQuickCheck('Q: The rabbit took out what\nA: A watch\nB: A key\nC: A hat', key), isNull);
      expect(parseQuickCheck('Q: What did the rabbit take out?\nA: A watch\nB: a watch\nC: A hat', key), isNull);
      expect(parseQuickCheck('Q: What did the rabbit take out?\nA: A watch\nB: Its waistcoat pocket\nC: A hat', key), isNull);
      expect(parseQuickCheck('Q: What did the rabbit take out?\nA: A watch', key), isNull);
    });

    test('teaser: one inviting sentence; meaning: the meaning alone', () {
      expect(parseTeaser('"A strange door waits at the end of the hall." Then more text follows.'),
          'A strange door waits at the end of the hall.');
      expect(parseTeaser('Too short.'), isNull);
      expect(parseMeaning('In this sentence, "sanguine" means hopeful and cheerful.', 'sanguine'), 'Hopeful and cheerful');
      expect(parseMeaning('It means feeling sleepy\nmore', 'drowsy'), 'Feeling sleepy');
      expect(parseMeaning('sanguine', 'sanguine'), isNull);
    });
  });

  group('planning', () {
    test('one block ahead: a recap and a check at each block end, a recap at the chapter end', () {
      List<String> plan(int from, {Set<String> tried = const {}}) => [
            for (final t in planLocalWork(total: 25, fromCard: from, every: 10, tried: tried)) '${t.kind.name}@${t.at}<${t.from}'
          ];
      expect(plan(0), ['teaser@-1<0', 'recap@9<0', 'check@9<0']);
      expect(plan(12), ['recap@19<10', 'check@19<10']);
      expect(plan(21), ['recap@24<20'], reason: 'no check at the end: the reflect card is there');
      expect(plan(0, tried: {'teaser', 'recap:9'}), ['check@9<0']);
      expect(planLocalWork(total: 4, fromCard: 0, every: 10, tried: {}).map((t) => t.kind), [LocalTaskKind.teaser]);
    });

    test('passages keep each card’s opening when a block is long', () {
      final cards = [
        for (var i = 0; i < 3; i++)
          SegmentCard(chapterIndex: 0, startSid: 's$i', endSid: 's$i', sentenceIds: ['s$i'], wordCount: 40),
      ];
      final text = {for (var i = 0; i < 3; i++) 's$i': List.filled(40, 'w$i').join(' ')};
      expect(passageFor(cards, text, 0, 2).split(RegExp(r'\s+')).length, 120);
      final short = passageFor(cards, text, 0, 2, maxWords: 60);
      expect(short.split('\n\n'), hasLength(3));
      expect(short.split('\n\n').first.split(' '), hasLength(20));
      expect(short.split('\n\n').first, endsWith('…'));
    });
  });

  test('merge: rule chapters gain recaps, checks and a teaser; AI chapters are left alone', () {
    const card = SegmentCard(chapterIndex: 0, startSid: 'a', endSid: 'a', sentenceIds: ['a'], wordCount: 10);
    const q = RecallQuestion(question: 'Why?', options: ['A', 'B', 'C'], answerIndex: 1);
    final merged = mergeLocal({
      0: const ChapterSegments(chapterIndex: 0, cards: [card], source: SegmentSource.rules),
      1: const ChapterSegments(chapterIndex: 1, cards: [card], source: SegmentSource.ai, teaser: 'AI teaser'),
    }, {
      0: LocalChapter(teaser: 'Local teaser', recaps: {0: ['One.', 'Two.']}, recalls: {0: q}),
      1: LocalChapter(teaser: 'Ignored'),
    });
    expect(merged[0]!.teaser, 'Local teaser');
    expect(merged[0]!.recaps[0], ['One.', 'Two.']);
    expect(merged[0]!.recalls[0]!.answerIndex, 1);
    expect(merged[1]!.teaser, 'AI teaser');
    final round = decodeLocal(encodeLocal({0: LocalChapter(teaser: 'T', recaps: {9: ['X.']}, recalls: {9: q}, tried: {'recap:9'})}));
    expect(round[0]!.recalls[9]!.question, 'Why?');
    expect(round[0]!.tried, {'recap:9'});
  });

  test('writing ahead: the model’s recap and check land in the feed after the right card', () async {
    final dir = Directory.systemTemp.createTempSync('localai');
    final store = await JsonStore.open(dir);
    addTearDown(() async {
      OnDeviceAiController.runtimeFactory = () => null;
      OnDeviceAiController.probeFactory = PlatformDeviceProbe.new;
      await store.flush();
      dir.deleteSync(recursive: true);
    });
    final runtime = FakeRuntime()..installed.add('qwen3-0.6b');
    runtime.llm = ScriptedLlm((p) {
      if (p.startsWith('Passage from')) return '- The rabbit hurries past Alice\n- Alice follows it to a hole';
      if (p.startsWith('Passage:')) return 'Q: What did the rabbit take out of its pocket?\nA: A watch\nB: A key\nC: A letter';
      return 'A strange hall of doors is waiting below.';
    });
    OnDeviceAiController.runtimeFactory = () => runtime;
    OnDeviceAiController.probeFactory = () => FakeProbe(const DeviceProfile(supported: true, totalRamBytes: 6 * gb));
    final c = ProviderContainer(overrides: [storeProvider.overrideWithValue(store)]);
    addTearDown(c.dispose);
    c.read(settingsProvider.notifier).update((s) => s.copyWith(localModel: 'qwen3-0.6b'));
    c.read(onDeviceAiProvider);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(c.read(onDeviceAiProvider.notifier).usable, isTrue);

    // Twelve cards of two sentences; card 5 holds the rabbit's watch.
    final sentences = [
      for (var i = 0; i < 24; i++)
        Sentence(
          id: 'c00.b000.s${i.toString().padLeft(2, '0')}',
          text: i == 10 ? 'The rabbit took a watch out of its waistcoat pocket and hurried on.' : 'Alice sat by the bank and watched the river go by, slowly.',
        ),
    ];
    final book = BookContent(title: 'Alice', author: 'Carroll', chapters: [
      Chapter(index: 0, title: 'Down the Rabbit-Hole', blocks: [Block(index: 0, type: BlockType.paragraph, sentences: sentences)]),
    ]);
    final seg = ChapterSegments(chapterIndex: 0, source: SegmentSource.rules, cards: [
      for (var i = 0; i < 12; i++)
        SegmentCard(
          chapterIndex: 0,
          startSid: sentences[2 * i].id,
          endSid: sentences[2 * i + 1].id,
          sentenceIds: [sentences[2 * i].id, sentences[2 * i + 1].id],
          wordCount: 24,
          keySids: i == 5 ? [sentences[10].id] : const [],
        ),
    ]);

    final writer = c.read(localAiSegmenterProvider);
    expect(await writer.ensure(bookId: 'b1', book: book, seg: seg, fromCard: 0, length: CardLength.standard, every: 10), isTrue);
    // Asked once each: teaser, recap, check.
    expect(runtime.llm.prompts, hasLength(3));
    expect(await writer.ensure(bookId: 'b1', book: book, seg: seg, fromCard: 0, length: CardLength.standard, every: 10), isFalse);
    expect(runtime.llm.prompts, hasLength(3), reason: 'done work is not asked for again');

    final local = decodeLocal(await store.readBlob(localBlobName('b1', CardLength.standard)));
    expect(local[0]!.teaser, 'A strange hall of doors is waiting below.');
    final feed = buildFeed(book, mergeLocal({0: seg}, local), const FeedOptions(maxReelWords: 0));
    final kinds = feed.map((f) => f.kind).toList();
    expect(feed.first.teaser, 'A strange hall of doors is waiting below.');
    final recapAt = kinds.indexOf(CardKind.recap);
    expect(feed[recapAt - 1].cardIndexInChapter, 9, reason: 'after the tenth card');
    expect(feed[recapAt].recapBullets, ['The rabbit hurries past Alice.', 'Alice follows it to a hole.']);
    expect(feed[recapAt + 1].kind, CardKind.recall);
    expect(feed[recapAt + 1].recall!.options[feed[recapAt + 1].recall!.answerIndex], 'A watch');
  });
}
