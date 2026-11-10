import 'dart:math' as math;

import '../models/book.dart';
import '../models/reel_card.dart';
import '../parsing/block_builder.dart';

/// Card length preferences (DESIGN.md §2.4).
enum CardLength {
  /// Social-feed default: one striking idea, 1–3 sentences.
  snack(min: 12, target: 30, max: 55),
  bite(min: 45, target: 75, max: 110),
  standard(min: 70, target: 120, max: 180),
  deep(min: 120, target: 180, max: 240);

  const CardLength({required this.min, required this.target, required this.max});

  final int min;
  final int target;
  final int max;
}

const _discourseMarkers = [
  'however', 'meanwhile', 'in contrast', 'on the other hand', 'nevertheless', 'later', 'the next',
  'first', 'second', 'third', 'finally', 'in conclusion', 'to begin', 'consider', 'another', 'now,',
];

const _backReferences = {
  'this', 'that', 'these', 'those', 'it', 'he', 'she', 'they', 'his', 'her', 'their', 'its', 'such',
  'but', 'and', 'so', 'thus', 'hence', 'therefore', 'yet', 'or', 'nor', 'also', 'then',
};

const _keyCues = [
  'the key', 'the point', 'the lesson', 'the secret', 'the truth', 'most important', 'importantly',
  'in short', 'in other words', 'the answer', 'the problem', 'the goal', 'the purpose', 'remember',
  'never', 'always', 'must', 'the best', 'the only', 'what matters', 'therefore', 'the reason',
];

class _Unit {
  _Unit(this.sentence, this.block, this.firstInBlock, this.lastInBlock);

  final Sentence sentence;
  final Block block;
  final bool firstInBlock;
  final bool lastInBlock;
  late final int words = sentence.wordCount;
}

/// Stage 1 segmenter (DESIGN.md §4.2). Scores every sentence boundary and
/// uses dynamic programming to choose cuts that keep cards inside the length
/// band while preferring strong boundaries. Never cuts inside a sentence and
/// avoids cutting inside quotes, lists and dialogue exchanges.
class RuleSegmenter {
  const RuleSegmenter({this.length = CardLength.standard});

  final CardLength length;

  ChapterSegments segment(Chapter chapter) {
    final units = <_Unit>[];
    final breakAfter = <int>{}; // unit index after which a scene break occurs
    for (final block in chapter.blocks) {
      if (isSceneBreakBlock(block)) {
        if (units.isNotEmpty) breakAfter.add(units.length - 1);
        continue;
      }
      for (var i = 0; i < block.sentences.length; i++) {
        units.add(_Unit(block.sentences[i], block, i == 0, i == block.sentences.length - 1));
      }
    }
    if (units.isEmpty) {
      return ChapterSegments(chapterIndex: chapter.index, cards: const [], source: SegmentSource.rules);
    }

    final n = units.length;
    // boundary[k] = score of cutting between unit k-1 and unit k (1 <= k < n).
    final boundary = List<double>.filled(n + 1, 0);
    boundary[n] = 1.0;
    for (var k = 1; k < n; k++) {
      boundary[k] = _boundaryScore(units[k - 1], units[k], breakAfter.contains(k - 1));
    }

    final prefix = List<int>.filled(n + 1, 0);
    for (var i = 0; i < n; i++) {
      prefix[i + 1] = prefix[i] + units[i].words;
    }

    final best = List<double>.filled(n + 1, double.negativeInfinity);
    final prev = List<int>.filled(n + 1, -1);
    best[0] = 0;
    final hardLimit = length.max * 2;
    for (var k = 1; k <= n; k++) {
      for (var j = k - 1; j >= 0; j--) {
        final words = prefix[k] - prefix[j];
        final single = j == k - 1;
        if (!single && words > hardLimit) break;
        if (best[j] == double.negativeInfinity) continue;
        final score = best[j] + boundary[k] - _lengthPenalty(words, single, isTail: k == n);
        if (score > best[k]) {
          best[k] = score;
          prev[k] = j;
        }
      }
    }

    final cuts = <int>[];
    for (var k = n; k > 0; k = prev[k]) {
      cuts.add(k);
    }
    cuts.add(0);
    final ordered = cuts.reversed.toList();

    final cards = <SegmentCard>[];
    for (var c = 0; c + 1 < ordered.length; c++) {
      final slice = units.sublist(ordered[c], ordered[c + 1]);
      cards.add(SegmentCard(
        chapterIndex: chapter.index,
        startSid: slice.first.sentence.id,
        endSid: slice.last.sentence.id,
        sentenceIds: [for (final u in slice) u.sentence.id],
        wordCount: slice.fold(0, (s, u) => s + u.words),
        type: _guessType(slice),
        standalone: !_startsWithBackReference(slice.first.sentence.text) || slice.first.firstInBlock && c == 0,
        keySids: _pickKeySentences(slice),
      ));
    }
    return ChapterSegments(chapterIndex: chapter.index, cards: cards, source: SegmentSource.rules);
  }

  double _boundaryScore(_Unit before, _Unit after, bool sceneBreak) {
    if (sceneBreak) return 1.2;
    if (before.block.type == BlockType.heading && before.block != after.block) {
      return -1.5; // keep a heading attached to the text that follows it
    }
    final sameBlock = identical(before.block, after.block) || before.block.index == after.block.index;
    double score;
    if (sameBlock) {
      switch (before.block.type) {
        case BlockType.quote:
        case BlockType.list:
        case BlockType.dialogue:
        case BlockType.preformatted:
          score = -1.0;
        case BlockType.heading:
          score = -1.5;
        case BlockType.paragraph:
          score = 0.05;
      }
    } else {
      score = 0.5;
      if (after.block.type == BlockType.heading) score += 0.6;
      if (before.block.type == BlockType.dialogue && after.block.type == BlockType.dialogue) score -= 0.6;
      if (before.block.type == BlockType.list && after.block.type == BlockType.list) score -= 0.5;
      final lower = after.sentence.text.toLowerCase();
      if (_discourseMarkers.any(lower.startsWith)) score += 0.2;
    }
    if (_startsWithBackReference(after.sentence.text)) score -= 0.5;
    return score;
  }

  double _lengthPenalty(int words, bool single, {required bool isTail}) {
    final t = length.target;
    var p = 0.6 * math.pow((words - t) / t, 2).toDouble();
    if (words < length.min) {
      // A short final card is acceptable when the chapter simply ends.
      p += (isTail ? 0.4 : 2.0) + 3.0 * (length.min - words) / length.min;
    }
    if (words > length.max && !single) {
      p += 2.0 + 3.0 * (words - length.max) / length.max;
    }
    return p;
  }
}

bool _startsWithBackReference(String text) {
  final m = RegExp(r'''^[\s“"'‘(]*([A-Za-z]+)''').firstMatch(text);
  return m != null && _backReferences.contains(m.group(1)!.toLowerCase());
}

String _guessType(List<_Unit> slice) {
  final types = slice.map((u) => u.block.type).toSet();
  if (types.contains(BlockType.dialogue)) return 'dialogue';
  if (types.contains(BlockType.list)) return 'example';
  if (types.contains(BlockType.quote)) return 'quote';
  return 'narrative';
}

List<String> _pickKeySentences(List<_Unit> slice) {
  String? bestId;
  var bestScore = 0.0;
  for (final u in slice) {
    if (u.block.type == BlockType.dialogue || u.block.type == BlockType.heading) continue;
    final lower = u.sentence.text.toLowerCase();
    var score = 0.0;
    for (final cue in _keyCues) {
      if (RegExp('\\b${RegExp.escape(cue)}\\b').hasMatch(lower)) score += 1.0;
    }
    if (u.words >= 8 && u.words <= 35) score += 0.3;
    if (u.firstInBlock) score += 0.1;
    if (score > bestScore) {
      bestScore = score;
      bestId = u.sentence.id;
    }
  }
  return bestScore >= 1.3 && bestId != null ? [bestId] : const [];
}
