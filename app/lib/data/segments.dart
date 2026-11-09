import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/book.dart';
import '../core/models/reel_card.dart';
import '../core/segmentation/rule_segmenter.dart';
import 'ai_client.dart';
import 'library.dart';
import 'settings_provider.dart';
import 'store_provider.dart';

typedef SegmentsKey = ({String bookId, CardLength length});

Map<int, ChapterSegments> _ruleSegment((BookContent, CardLength) args) {
  final segmenter = RuleSegmenter(length: args.$2);
  return {for (final c in args.$1.chapters) c.index: segmenter.segment(c)};
}

String _encodeSegments(Map<int, ChapterSegments> m) =>
    jsonEncode({for (final e in m.entries) '${e.key}': e.value.toJson()});

Map<int, ChapterSegments> _decodeSegments(String s) => (jsonDecode(s) as Map<String, dynamic>)
    .map((k, v) => MapEntry(int.parse(k), ChapterSegments.fromJson(v as Map<String, dynamic>)));

/// Rule segments for every chapter, with AI segments (when cached) replacing
/// them chapter by chapter. Rule segments are computed in a background isolate
/// and cached on disk.
final segmentsProvider = FutureProvider.family<Map<int, ChapterSegments>, SegmentsKey>((ref, key) async {
  final store = ref.read(storeProvider);
  final book = await ref.watch(bookContentProvider(key.bookId).future);
  final rulesName = '${key.bookId}.rules.${key.length.name}.json';
  Map<int, ChapterSegments> rules;
  final cached = await store.readBlob(rulesName);
  if (cached != null) {
    rules = await compute(_decodeSegments, cached);
  } else {
    rules = await compute(_ruleSegment, (book, key.length));
    await store.writeBlob(rulesName, await compute(_encodeSegments, rules));
  }
  final aiRaw = await store.readBlob('${key.bookId}.ai.${key.length.name}.json');
  if (aiRaw == null) return rules;
  final ai = await compute(_decodeSegments, aiRaw);
  return {...rules, ...ai};
});

final deviceIdProvider = Provider<String>((ref) {
  final store = ref.read(storeProvider);
  final existing = store.doc('device')?['id'] as String?;
  if (existing != null) return existing;
  final id = newDeviceId();
  store.saveDoc('device', {'id': id});
  return id;
});

final aiClientProvider = Provider<AiSegmentationClient>(
    (ref) => AiSegmentationClient(baseUrl: bookreelApi, deviceId: ref.read(deviceIdProvider)));

/// Just-in-time AI segmentation (DESIGN.md §4.3): the chapter being read and
/// the next one are requested in real time; failures silently keep rule cards.
class AiSegmenter {
  AiSegmenter(this.ref);
  final Ref ref;
  final Set<String> _inFlight = {};

  Future<bool> ensureChapters(String bookId, BookContent book, List<int> chapters) async {
    final settings = ref.read(settingsProvider);
    final client = ref.read(aiClientProvider);
    if (!client.enabled || settings.tier.name == 'free') return false;
    final store = ref.read(storeProvider);
    final name = '$bookId.ai.${settings.cardLength.name}.json';
    final existingRaw = await store.readBlob(name);
    final existing = existingRaw == null ? <int, ChapterSegments>{} : await compute(_decodeSegments, existingRaw);
    final missing = chapters
        .where((c) => c < book.chapters.length && !existing.containsKey(c) && _inFlight.add('$bookId:$c'))
        .toList();
    if (missing.isEmpty) return false;
    try {
      final result = await client.segmentChapters(
        bookId: bookId,
        book: book,
        chapterIndexes: missing,
        tier: settings.tier,
        length: settings.cardLength,
        level: settings.readingLevel,
      );
      if (result.isEmpty) return false;
      final merged = {...existing, ...result};
      await store.writeBlob(name, await compute(_encodeSegments, merged));
      return true;
    } on AiUnavailable catch (e) {
      debugPrint(e.toString());
      return false;
    } finally {
      for (final c in missing) {
        _inFlight.remove('$bookId:$c');
      }
    }
  }
}

final aiSegmenterProvider = Provider<AiSegmenter>(AiSegmenter.new);
