import 'dart:convert';
import 'dart:io';

import 'package:book_reel/core/models/reel_card.dart';
import 'package:book_reel/core/parsing/epub_parser.dart';
import 'package:book_reel/core/segmentation/rule_segmenter.dart';
import 'package:book_reel/core/text/lexicon.dart';
import 'package:book_reel/data/ai_client.dart';
import 'package:book_reel/data/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final book = const EpubParser().parse(File('assets/books/alice.epub').readAsBytesSync()).content;
  final chapter = book.chapters[0];
  final sids = chapter.sentences.map((s) => s.id).toList();

  Map<String, dynamic> serverChapter() {
    final mid = sids.length ~/ 2;
    return {
      'index': 0,
      'source': 'ai',
      'cards': [
        {
          'start_sid': sids.first,
          'end_sid': sids[mid - 1],
          'title': 'Down the hole',
          'type': 'narrative',
          'standalone': true,
          'key_sids': [sids[1], sids.last], // second one is outside the card and must be dropped
          'hard_words': [
            {'word': 'curiosity', 'sid': sids[2], 'meaning': 'eager wish to know'},
          ],
          'mood': 'mysterious',
          'energy': 2,
          'layout': 'centered',
          'emphasis': [
            {'sid': sids[1], 'text': 'Alice', 'level': 3},
            {'sid': 'c9.b9.s9', 'text': 'elsewhere', 'level': 2}, // not in this card: dropped
          ],
        },
        {
          'start_sid': sids[mid],
          'end_sid': sids.last,
          'type': 'narrative',
          'standalone': false,
          'key_sids': <String>[],
          'hard_words': <Map<String, dynamic>>[],
        },
      ],
      'recaps': [
        {'after_card': 1, 'bullets': ['Alice follows the Rabbit.']},
      ],
      'recalls': [
        {'after_card': 0, 'question': 'Why does Alice follow?', 'options': ['Curiosity', 'Fear', 'Hunger'], 'answer_index': 0},
      ],
      'teaser': 'A white rabbit with a pocket watch.',
      'scene': 'meadow',
      'scene_cues': [
        {'at_card': 1, 'scene': 'night'},
      ],
      'music_cues': [
        {'at_card': 0, 'mood': 'playful', 'energy': 2, 'description': 'light pizzicato'},
        {'at_card': 1, 'mood': 'mysterious', 'energy': 3, 'description': 'soft synth pads'},
      ],
    };
  }

  test('parses server chapters and expands sentence ranges locally', () {
    final seg = parseServerChapter(chapter, serverChapter())!;
    expect(seg.source, SegmentSource.ai);
    expect(seg.cards, hasLength(2));
    expect(seg.cards.expand((c) => c.sentenceIds).toList(), sids);
    expect(seg.cards.first.keySids, [sids[1]]);
    expect(seg.cards.first.hardWords.single.meaning, 'eager wish to know');
    expect(seg.cards.first.mood, 'mysterious');
    expect(seg.cards.first.energy, 2);
    expect(seg.cards.last.mood, isNull);
    expect(seg.cards.first.layout, 'centered');
    expect(seg.cards.first.emphasis.map((e) => (e.text, e.level)), [('Alice', 3)]);
    expect(seg.scene, 'meadow');
    expect(seg.sceneAt(0), 'meadow');
    expect(seg.sceneAt(1), 'night');
    expect(seg.musicCues.map((c) => (c.atCard, c.mood)), [(0, 'playful'), (1, 'mysterious')]);
    // Survives the on-disk cache round trip.
    final copy = ChapterSegments.fromJson(seg.toJson());
    expect(copy.sceneAt(1), 'night');
    expect(copy.musicCues.last.description, 'soft synth pads');
    expect(copy.cards.first.emphasis.single.text, 'Alice');
    expect(seg.recalls[0]!.options.first, 'Curiosity');
    expect(seg.recaps[1], ['Alice follows the Rabbit.']);
  });

  test('rejects server chapters that do not cover the chapter exactly', () {
    final bad = serverChapter();
    (bad['cards'] as List).removeLast();
    expect(parseServerChapter(chapter, bad), isNull);
  });

  test('client posts chapters with the device id and maps quota errors', () async {
    late Map<String, dynamic> sent;
    final ok = MockClient((req) async {
      sent = jsonDecode(req.body) as Map<String, dynamic>;
      expect(req.headers['x-device-id'], 'dev123');
      return http.Response(jsonEncode({'chapters': [serverChapter()]}), 200);
    });
    final client = AiSegmentationClient(baseUrl: 'http://x', deviceId: 'dev123', httpClient: ok);
    final result = await client.segmentChapters(
      bookId: 'a' * 64,
      book: book,
      chapterIndexes: [0],
      tier: Tier.pro,
      length: CardLength.standard,
      level: ReadingLevel.intermediate,
    );
    expect(result[0]!.cards, hasLength(2));
    expect(sent['tier'], 'pro');
    expect((sent['chapters'] as List).single['sentences'], hasLength(sids.length));

    final quota = AiSegmentationClient(
        baseUrl: 'http://x', deviceId: 'd', httpClient: MockClient((_) async => http.Response('{}', 402)));
    expect(
      () => quota.segmentChapters(
          bookId: 'a' * 64, book: book, chapterIndexes: [0], tier: Tier.pro, length: CardLength.standard, level: ReadingLevel.intermediate),
      throwsA(isA<AiUnavailable>()),
    );
    expect(
      () => quota.segmentChapters(
          bookId: 'a' * 64, book: book, chapterIndexes: [0], tier: Tier.free, length: CardLength.standard, level: ReadingLevel.intermediate),
      throwsA(isA<AiUnavailable>()),
    );
  });
}
