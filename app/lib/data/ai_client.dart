import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../core/models/book.dart';
import '../core/models/reel_card.dart';
import '../core/segmentation/rule_segmenter.dart';
import '../core/text/lexicon.dart';
import 'settings.dart';

/// Backend base URL, e.g. `--dart-define=BOOKREEL_API=http://10.0.2.2:8787`.
/// Empty means AI segmentation is unavailable and rule cards are used.
const bookreelApi = String.fromEnvironment('BOOKREEL_API');

class AiUnavailable implements Exception {
  AiUnavailable(this.reason);
  final String reason;
  @override
  String toString() => 'AI segmentation unavailable: $reason';
}

/// Client for `POST /v1/segment` (server/src/routes/segment.ts).
class AiSegmentationClient {
  AiSegmentationClient({required this.baseUrl, required this.deviceId, http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final String baseUrl;
  final String deviceId;
  final http.Client _http;

  bool get enabled => baseUrl.isNotEmpty;

  Future<Map<int, ChapterSegments>> segmentChapters({
    required String bookId,
    required BookContent book,
    required List<int> chapterIndexes,
    required Tier tier,
    required CardLength length,
    required ReadingLevel level,
    bool background = false,
  }) async {
    if (!enabled) throw AiUnavailable('no server configured');
    if (tier == Tier.free) throw AiUnavailable('free tier uses on-device segmentation');
    final chapters = [for (final i in chapterIndexes) book.chapters[i]];
    final body = {
      'book': {'content_hash': bookId, 'title': book.title, 'author': book.author, 'language': book.language},
      'tier': tier.name,
      'card_length': length.name,
      'reading_level': level.name,
      'priority': background ? 'background' : 'now',
      'chapters': [
        for (final c in chapters)
          {
            'index': c.index,
            'title': c.title,
            'context_before': _contextBefore(book, c.index),
            'sentences': [
              for (final b in c.blocks)
                for (final s in b.sentences) {'sid': s.id, 'text': s.text, 'block': b.type.name},
            ],
          },
      ],
    };
    final http.Response res;
    try {
      res = await _http
          .post(
            Uri.parse('$baseUrl/v1/segment'),
            headers: {'content-type': 'application/json', 'x-device-id': deviceId},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 120));
    } catch (e) {
      throw AiUnavailable('network: $e');
    }
    if (res.statusCode == 402) throw AiUnavailable('monthly AI book quota reached');
    if (res.statusCode != 200) throw AiUnavailable('server returned ${res.statusCode}');
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final out = <int, ChapterSegments>{};
    for (final c in (json['chapters'] as List).cast<Map<String, dynamic>>()) {
      final index = c['index'] as int;
      final chapter = book.chapters.where((x) => x.index == index).firstOrNull;
      if (chapter == null) continue;
      final parsed = parseServerChapter(chapter, c);
      if (parsed != null) out[index] = parsed;
    }
    return out;
  }

  String _contextBefore(BookContent book, int index) {
    if (index == 0) return '';
    final prev = book.chapters[index - 1].sentences.toList();
    final tail = <String>[];
    var words = 0;
    for (final s in prev.reversed) {
      tail.insert(0, s.text);
      words += s.wordCount;
      if (words > 250) break;
    }
    return tail.join(' ');
  }
}

/// Converts the server's chapter JSON into [ChapterSegments], expanding
/// sentence ranges locally. Returns null if the ranges don't cover the
/// chapter exactly (the server validates too; this is a second guard).
ChapterSegments? parseServerChapter(Chapter chapter, Map<String, dynamic> json) {
  final order = [for (final s in chapter.sentences) s];
  final position = {for (var i = 0; i < order.length; i++) order[i].id: i};
  final cards = <SegmentCard>[];
  var expected = 0;
  for (final c in (json['cards'] as List).cast<Map<String, dynamic>>()) {
    final start = position[c['start_sid']];
    final end = position[c['end_sid']];
    if (start == null || end == null || start != expected || end < start) return null;
    final slice = order.sublist(start, end + 1);
    final sids = {for (final s in slice) s.id};
    cards.add(SegmentCard(
      chapterIndex: chapter.index,
      startSid: slice.first.id,
      endSid: slice.last.id,
      sentenceIds: sids.toList(),
      wordCount: slice.fold(0, (s, x) => s + x.wordCount),
      title: c['title'] as String?,
      hook: c['hook'] as String?,
      type: (c['type'] as String?) ?? 'narrative',
      standalone: (c['standalone'] as bool?) ?? true,
      keySids: ((c['key_sids'] as List?) ?? const []).cast<String>().where(sids.contains).toList(),
      hardWords: [
        for (final h in ((c['hard_words'] as List?) ?? const []).cast<Map<String, dynamic>>())
          if (sids.contains(h['sid'])) HardWord.fromJson(h),
      ],
    ));
    expected = end + 1;
  }
  if (expected != order.length) return null;
  return ChapterSegments(
    chapterIndex: chapter.index,
    cards: cards,
    source: SegmentSource.ai,
    teaser: json['teaser'] as String?,
    recaps: {
      for (final r in ((json['recaps'] as List?) ?? const []).cast<Map<String, dynamic>>())
        r['after_card'] as int: (r['bullets'] as List).cast<String>(),
    },
    recalls: {
      for (final r in ((json['recalls'] as List?) ?? const []).cast<Map<String, dynamic>>())
        r['after_card'] as int: RecallQuestion.fromJson(r),
    },
  );
}

String newDeviceId() {
  final r = Random.secure();
  return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}
