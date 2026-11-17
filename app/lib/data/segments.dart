import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/book.dart';
import '../core/models/reel_card.dart';
import '../core/segmentation/rule_segmenter.dart';
import 'ai_client.dart';
import 'library.dart';
import 'local_ai.dart';
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

/// Decodes the AI's segments in [raw], except chapters stored exactly as in
/// [previous] (the last copy decoded): those are listed instead, so the
/// objects already in memory can be kept for them.
(Map<int, ChapterSegments>, Set<int>) _decodeChanged((String, String?) args) {
  final (raw, previous) = args;
  final now = jsonDecode(raw) as Map<String, dynamic>;
  final before = previous == null ? const <String, dynamic>{} : jsonDecode(previous) as Map<String, dynamic>;
  final decoded = <int, ChapterSegments>{};
  final same = <int>{};
  for (final e in now.entries) {
    final k = int.parse(e.key);
    if (before.containsKey(e.key) && jsonEncode(before[e.key]) == jsonEncode(e.value)) {
      same.add(k);
    } else {
      decoded[k] = ChapterSegments.fromJson(e.value as Map<String, dynamic>);
    }
  }
  return (decoded, same);
}

/// Segments already decoded, by blob name (with the text they came from), so
/// a reload when the on-device model or the AI adds to a book keeps the very
/// same objects for every chapter that didn't change. The reader then keeps
/// those chapters' reels instead of laying the whole book out again
/// (`FeedCache`), which on a long book took long enough to freeze a swipe.
final _decoded = <String, (String, Map<int, ChapterSegments>)>{};

void _remember(String name, String raw, Map<int, ChapterSegments> segments) {
  _decoded.remove(name);
  _decoded[name] = (raw, segments);
  // A few books' worth: the one being read, and a couple just before it.
  while (_decoded.length > 6) {
    _decoded.remove(_decoded.keys.first);
  }
}

/// Rule segments for every chapter, with AI segments (when cached) replacing
/// them chapter by chapter, and on-device extras added to rule chapters. Rule
/// segments are computed in a background isolate and cached on disk.
final segmentsProvider = FutureProvider.family<Map<int, ChapterSegments>, SegmentsKey>((ref, key) async {
  final store = ref.read(storeProvider);
  final book = await ref.watch(bookContentProvider(key.bookId).future);
  final rulesName = '${key.bookId}.rules.${key.length.name}.json';
  Map<int, ChapterSegments> rules;
  final cached = await store.readBlob(rulesName);
  final known = _decoded[rulesName];
  if (cached != null && known != null && known.$1 == cached) {
    rules = known.$2;
  } else if (cached != null) {
    rules = await compute(_decodeSegments, cached);
    _remember(rulesName, cached, rules);
  } else {
    rules = await compute(_ruleSegment, (book, key.length));
    final raw = await compute(_encodeSegments, rules);
    await store.writeBlob(rulesName, raw);
    _remember(rulesName, raw, rules);
  }
  final aiName = '${key.bookId}.ai.${key.length.name}.json';
  final aiRaw = await store.readBlob(aiName);
  Map<int, ChapterSegments>? ai;
  if (aiRaw != null) {
    final before = _decoded[aiName];
    if (before != null && before.$1 == aiRaw) {
      ai = before.$2;
    } else {
      final (fresh, same) = await compute(_decodeChanged, (aiRaw, before?.$1));
      ai = {...fresh, for (final k in same) k: before!.$2[k]!};
      _remember(aiName, aiRaw, ai);
    }
  }
  final merged = ai == null ? rules : {...rules, ...ai};
  // Free: recaps, quick checks and teasers the on-device model wrote.
  final localRaw = await store.readBlob(localBlobName(key.bookId, key.length));
  return localRaw == null ? merged : mergeLocal(merged, decodeLocal(localRaw));
});

final deviceIdProvider = Provider<String>((ref) {
  final store = ref.read(storeProvider);
  final existing = store.doc('device')?['id'] as String?;
  if (existing != null) return existing;
  final id = newDeviceId();
  store.saveDoc('device', {'id': id});
  return id;
});

final aiClientProvider = Provider<AiSegmentationClient>((ref) => AiSegmentationClient(
      baseUrl: ref.watch(settingsProvider.select((s) => s.online)) ? bookreelApi : '',
      deviceId: ref.watch(deviceIdProvider),
    ));

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
