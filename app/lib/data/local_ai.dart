import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/book.dart';
import '../core/models/reel_card.dart';
import '../core/segmentation/rule_segmenter.dart';
import '../services/on_device_ai.dart';
import 'store_provider.dart';

/// What the on-device model adds to Free reading (DESIGN.md §4.3): a recap
/// and a quick check every few minutes of reading, a recap at the end of a
/// chapter, a teaser on the chapter's title card, and word meanings in
/// context. The model never changes the book's text or where cards are cut:
/// the rule segmenter still does that. Every reply is checked before it is
/// shown; one that fails a check is dropped, and the rule cards stay.

// ---------------------------------------------------------------- prompts

const localSystemPrompt =
    'You help someone with the book they are reading. Use only what the text says. Be brief, plain and accurate.';

String recapPrompt(String book, String passage) => '''Passage from "$book":
"""
$passage
"""

Recap this passage in 2 or 3 short bullet points, each under 20 words, in the order things happen. Start each bullet with "- ". Write nothing else.''';

String quickCheckPrompt(String passage, String keySentence) => '''Passage:
"""
$passage
"""

Key sentence: "$keySentence"

Write one multiple-choice question about the key sentence. The correct answer must use words from the key sentence; the two wrong answers must be believable but wrong. Use exactly this format:
Q: the question?
A: the correct answer
B: a wrong answer
C: a wrong answer''';

String teaserPrompt(String book, String chapter, String opening) => '''The opening of the chapter "$chapter" in "$book":
"""
$opening
"""

Write one short, inviting sentence (under 18 words) about how this chapter begins, without giving anything away. Write only that sentence.''';

String meaningPrompt(String word, String sentence) => '''Sentence: "$sentence"

What does "$word" mean in this sentence? Reply with a short meaning (under 15 words) that fits this sentence. Write only the meaning.''';

// ---------------------------------------------------------------- checks

final _think = RegExp(r'<think>[\s\S]*?(</think>|$)');
final _space = RegExp(r'\s+');

int _wordCount(String s) => s.trim().isEmpty ? 0 : s.trim().split(_space).length;

/// Strips thinking, markdown emphasis and wrapping quotes; one line.
String tidyReply(String s) {
  var t = s.replaceAll(_think, '').replaceAll('**', '').replaceAll('__', '').replaceAll(_space, ' ').trim();
  t = t.replaceFirst(RegExp(r'''^["“”'‘’]+'''), '').replaceFirst(RegExp(r'''["“”'‘’]+$'''), '').trim();
  return t;
}

String _sentenceCase(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

String _withStop(String s) => RegExp(r'[.!?…”"]$').hasMatch(s) ? s : '$s.';

/// 2–3 recap bullets, or null when the reply is not usable.
List<String>? parseBullets(String raw) {
  final out = <String>[];
  for (final line in raw.replaceAll(_think, '').split('\n')) {
    final m = RegExp(r'^\s*(?:[-•*–]|\d+[.)])\s+(.+)$').firstMatch(line);
    if (m == null) continue;
    final b = _withStop(_sentenceCase(tidyReply(m.group(1)!)));
    final words = _wordCount(b);
    if (words < 3 || words > 28) continue;
    // "Here is a recap of the passage:" and the like.
    if (RegExp(r'\b(passage|bullet points?|recap|summary)\b', caseSensitive: false).hasMatch(b) && words < 9) continue;
    if (out.any((o) => o.toLowerCase() == b.toLowerCase())) continue;
    out.add(b);
    if (out.length == 3) break;
  }
  return out.length >= 2 ? out : null;
}

const _stopWords = {
  'the', 'and', 'for', 'was', 'were', 'are', 'his', 'her', 'its', 'their', 'with', 'that', 'this', 'from', 'into',
  'had', 'has', 'have', 'not', 'but', 'they', 'she', 'him', 'them', 'who', 'what', 'when', 'than', 'then', 'very',
  'all', 'any', 'one', 'out', 'off', 'over', 'upon', 'our', 'your', 'you', 'did', 'does', 'been', 'being', 'will',
};

Iterable<String> _contentWords(String s) => s
    .toLowerCase()
    .split(RegExp(r"[^a-z0-9']+"))
    .map((w) => w.replaceAll(RegExp(r"'s$"), '').replaceAll("'", ''))
    .where((w) => w.length >= 3 && !_stopWords.contains(w));

String _stem(String w) => w.length > 4 && w.endsWith('s') ? w.substring(0, w.length - 1) : w;

/// How much of [answer]'s content appears in [source] (0–1).
double _grounding(String answer, String source) {
  final words = _contentWords(answer).map(_stem).toSet();
  if (words.isEmpty) return 0;
  final src = _contentWords(source).map(_stem).toSet();
  return words.where(src.contains).length / words.length;
}

/// A quick check whose right answer comes from [keySentence], or null.
/// [seed] places the right answer among the options.
RecallQuestion? parseQuickCheck(String raw, String keySentence, {int seed = 0}) {
  String? field(String letter) {
    final m = RegExp('^\\s*(?:\\*\\*)?$letter(?:\\*\\*)?\\s*[:.)]\\s*(.+)\$', multiLine: true, caseSensitive: false)
        .firstMatch(raw.replaceAll(_think, ''));
    return m == null ? null : tidyReply(m.group(1)!);
  }

  final q = field('(?:Q|Question)');
  final a = field('A');
  final b = field('B');
  final c = field('C');
  if (q == null || a == null || b == null || c == null) return null;
  final question = _sentenceCase(q);
  if (!question.endsWith('?') || _wordCount(question) < 4 || _wordCount(question) > 25) return null;
  final options = [a, b, c].map((o) => _sentenceCase(o.replaceFirst(RegExp(r'[.;]$'), ''))).toList();
  if (options.any((o) => o.isEmpty || _wordCount(o) > 12)) return null;
  if (options.map((o) => o.toLowerCase()).toSet().length != 3) return null;
  // The right answer must be grounded in the book; the wrong ones must not
  // simply restate it.
  if (_grounding(options[0], keySentence) < 0.6) return null;
  for (final wrong in options.skip(1)) {
    if (_contentWords(wrong).isNotEmpty && _grounding(wrong, keySentence) == 1) return null;
  }
  final shift = seed.abs() % 3;
  final shuffled = [for (var i = 0; i < 3; i++) options[(i - shift) % 3]];
  return RecallQuestion(question: question, options: shuffled, answerIndex: shift);
}

/// One teaser sentence, or null.
String? parseTeaser(String raw) {
  var t = tidyReply(raw);
  final first = RegExp(r'''^(.+?[.!?…])["”’']*(?:\s|$)''').firstMatch(t);
  if (first != null) t = first.group(1)!;
  final words = _wordCount(t);
  if (words < 4 || words > 24) return null;
  return _withStop(_sentenceCase(t));
}

/// A short meaning of [word], or null.
String? parseMeaning(String raw, String word) {
  var t = tidyReply(raw.split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => ''));
  final w = RegExp.escape(word);
  t = t
      .replaceFirst(RegExp(r'^in (this|the) sentence,?\s*', caseSensitive: false), '')
      .replaceFirst(RegExp('^["“]?$w["”]?\\s+(here\\s+)?(means|refers to|is)\\s+', caseSensitive: false), '')
      .replaceFirst(RegExp(r'^(it\s+)?(means|meaning:)\s*', caseSensitive: false), '')
      .trim();
  final words = _wordCount(t);
  if (words < 1 || words > 20 || t.toLowerCase() == word.toLowerCase()) return null;
  return _sentenceCase(t.replaceFirst(RegExp(r'\.$'), ''));
}

// ---------------------------------------------------------------- writer

/// Asks a loaded model for each kind of help and checks the reply.
class LocalWriter {
  const LocalWriter();

  Future<List<String>?> recap(LocalLlm llm, {required String book, required String passage}) async =>
      parseBullets(await llm.generate(recapPrompt(book, passage), system: localSystemPrompt, maxOutputTokens: 170, temperature: 0.2));

  Future<RecallQuestion?> quickCheck(LocalLlm llm, {required String passage, required String keySentence, int seed = 0}) async =>
      parseQuickCheck(
        await llm.generate(quickCheckPrompt(passage, keySentence), system: localSystemPrompt, maxOutputTokens: 120, temperature: 0.3),
        keySentence,
        seed: seed,
      );

  Future<String?> teaser(LocalLlm llm, {required String book, required String chapter, required String opening}) async =>
      parseTeaser(await llm.generate(teaserPrompt(book, chapter, opening), system: localSystemPrompt, maxOutputTokens: 48, temperature: 0.5));

  Future<String?> meaning(LocalLlm llm, {required String word, required String sentence}) async =>
      parseMeaning(await llm.generate(meaningPrompt(word, sentence), system: localSystemPrompt, maxOutputTokens: 40, temperature: 0.1), word);
}

// ---------------------------------------------------------------- storage

/// What the model wrote for one chapter.
class LocalChapter {
  LocalChapter({this.teaser, Map<int, List<String>>? recaps, Map<int, RecallQuestion>? recalls, Set<String>? tried})
      : recaps = recaps ?? {},
        recalls = recalls ?? {},
        tried = tried ?? {};

  String? teaser;

  /// Keyed by the index of the card they follow.
  final Map<int, List<String>> recaps;
  final Map<int, RecallQuestion> recalls;

  /// Work already attempted ("teaser", "recap:9", "check:9"), kept so a
  /// reply that failed its checks is not asked for again.
  final Set<String> tried;

  Map<String, dynamic> toJson() => {
        if (teaser != null) 'teaser': teaser,
        'recaps': recaps.map((k, v) => MapEntry('$k', v)),
        'recalls': recalls.map((k, v) => MapEntry('$k', v.toJson())),
        'tried': tried.toList(),
      };

  factory LocalChapter.fromJson(Map<String, dynamic> j) => LocalChapter(
        teaser: j['teaser'] as String?,
        recaps: ((j['recaps'] as Map?) ?? const {}).map((k, v) => MapEntry(int.parse(k as String), (v as List).cast<String>())),
        recalls: ((j['recalls'] as Map?) ?? const {})
            .map((k, v) => MapEntry(int.parse(k as String), RecallQuestion.fromJson(v as Map<String, dynamic>))),
        tried: ((j['tried'] as List?) ?? const []).cast<String>().toSet(),
      );
}

/// Per book and card length (rule cards differ by length).
String localBlobName(String bookId, CardLength length) => '$bookId.local.${length.name}.json';

String encodeLocal(Map<int, LocalChapter> m) => jsonEncode({for (final e in m.entries) '${e.key}': e.value.toJson()});

Map<int, LocalChapter> decodeLocal(String? s) => s == null
    ? {}
    : (jsonDecode(s) as Map<String, dynamic>).map((k, v) => MapEntry(int.parse(k), LocalChapter.fromJson(v as Map<String, dynamic>)));

/// Adds what the model wrote to rule-cut chapters (cloud AI chapters already
/// have their own recaps and checks).
Map<int, ChapterSegments> mergeLocal(Map<int, ChapterSegments> segments, Map<int, LocalChapter> local) {
  if (local.isEmpty) return segments;
  final out = {...segments};
  for (final e in local.entries) {
    final seg = out[e.key];
    if (seg == null || seg.source != SegmentSource.rules) continue;
    out[e.key] = ChapterSegments(
      chapterIndex: seg.chapterIndex,
      cards: seg.cards,
      source: seg.source,
      recaps: {...seg.recaps, ...e.value.recaps},
      recalls: {...seg.recalls, ...e.value.recalls},
      teaser: seg.teaser ?? e.value.teaser,
      scene: seg.scene,
      sceneCues: seg.sceneCues,
    );
  }
  return out;
}

// ---------------------------------------------------------------- planning

enum LocalTaskKind { teaser, recap, check }

typedef LocalTask = ({LocalTaskKind kind, int at, int from});

String _triedKey(LocalTask t) => t.kind == LocalTaskKind.teaser ? 'teaser' : '${t.kind.name}:${t.at}';

/// What to write next in a chapter of [total] cards, for a reader at card
/// [fromCard]: the teaser (only before the first card), then a recap and a
/// quick check at the next [lookahead] block ends (every [every] cards), and
/// a recap at the chapter's end. Work already [tried] is skipped.
List<LocalTask> planLocalWork({
  required int total,
  required int fromCard,
  required int every,
  required Set<String> tried,
  int lookahead = 1,
}) {
  final tasks = <LocalTask>[];
  if (fromCard <= 0 && total >= 3) tasks.add((kind: LocalTaskKind.teaser, at: -1, from: 0));
  final ends = <int>[
    for (var e = every - 1; e < total - 1; e += every) e,
    if (total >= 5) total - 1,
  ];
  var start = 0;
  var upcoming = 0;
  for (final e in ends) {
    final from = start;
    start = e + 1;
    if (e < fromCard) continue;
    if (upcoming++ >= lookahead) break;
    tasks.add((kind: LocalTaskKind.recap, at: e, from: from));
    // No check at the chapter's end: the reflect card is there.
    if (e < total - 1) tasks.add((kind: LocalTaskKind.check, at: e, from: from));
  }
  return [for (final t in tasks) if (!tried.contains(_triedKey(t))) t];
}

/// The text of cards [from]..[to], at most [maxWords] (each card keeps its
/// opening when the block is long).
String passageFor(List<SegmentCard> cards, Map<String, String> text, int from, int to, {int maxWords = 900}) {
  final slice = cards.sublist(from, to + 1);
  final total = slice.fold(0, (n, c) => n + c.wordCount);
  final perCard = total <= maxWords ? null : (maxWords / slice.length).floor().clamp(20, maxWords);
  final parts = <String>[];
  for (final c in slice) {
    final words = c.sentenceIds.map((id) => text[id] ?? '').where((s) => s.isNotEmpty).join(' ').split(_space);
    parts.add(perCard == null || words.length <= perCard ? words.join(' ') : '${words.take(perCard).join(' ')}…');
  }
  return parts.join('\n\n');
}

/// A sentence worth checking in cards [from]..[to]: a rule key sentence,
/// else the block's middle sentence of a sensible length.
String? keySentenceFor(List<SegmentCard> cards, Map<String, String> text, int from, int to) {
  final slice = cards.sublist(from, to + 1);
  for (final c in slice.reversed) {
    for (final id in c.keySids) {
      final s = text[id];
      if (s != null && _wordCount(s) >= 6 && _wordCount(s) <= 40) return s;
    }
  }
  final ids = [for (final c in slice) ...c.sentenceIds];
  final fitting = ids.map((id) => text[id] ?? '').where((s) {
    final n = _wordCount(s);
    return n >= 8 && n <= 32 && !s.contains('“') && !s.contains('"');
  }).toList();
  if (fitting.isEmpty) return null;
  return fitting[fitting.length ~/ 2];
}

// ---------------------------------------------------------------- runner

/// Writes on-device extras just ahead of the reader, a block at a time.
class LocalAiSegmenter {
  LocalAiSegmenter(this.ref, {this.writer = const LocalWriter()});
  final Ref ref;
  final LocalWriter writer;
  final Set<String> _running = {};

  /// Writes what the reader will reach next in [seg]'s chapter. Returns true
  /// when something new was saved (the reader then reloads its cards).
  Future<bool> ensure({
    required String bookId,
    required BookContent book,
    required ChapterSegments seg,
    required int fromCard,
    required CardLength length,
    required int every,
  }) async {
    final ai = ref.read(onDeviceAiProvider.notifier);
    if (!ai.usable || seg.source != SegmentSource.rules || seg.cards.isEmpty) return false;
    final key = '$bookId:${seg.chapterIndex}';
    if (!_running.add(key)) return false;
    try {
      final store = ref.read(storeProvider);
      final name = localBlobName(bookId, length);
      final all = decodeLocal(await store.readBlob(name));
      final local = all[seg.chapterIndex] ??= LocalChapter();
      final plan = planLocalWork(total: seg.cards.length, fromCard: fromCard, every: every, tried: local.tried);
      if (plan.isEmpty) return false;
      final chapter = book.chapters.where((c) => c.index == seg.chapterIndex).firstOrNull;
      if (chapter == null) return false;
      final text = {for (final b in chapter.blocks) for (final s in b.sentences) s.id: s.text};
      var changed = false;
      for (final task in plan) {
        if (!ai.usable) break;
        switch (task.kind) {
          case LocalTaskKind.teaser:
            final opening = passageFor(seg.cards, text, 0, (seg.cards.length - 1).clamp(0, 3), maxWords: 350);
            final t = await ai.run((llm) => writer.teaser(llm, book: book.title, chapter: chapter.title, opening: opening));
            if (t != null) local.teaser = t;
            changed |= t != null;
          case LocalTaskKind.recap:
            final passage = passageFor(seg.cards, text, task.from, task.at);
            final r = await ai.run((llm) => writer.recap(llm, book: book.title, passage: passage));
            if (r != null) local.recaps[task.at] = r;
            changed |= r != null;
          case LocalTaskKind.check:
            final key = keySentenceFor(seg.cards, text, task.from, task.at);
            if (key == null) break;
            // The card around the key sentence is enough context.
            final at = seg.cards.indexWhere((c) => c.sentenceIds.any((id) => text[id] == key), task.from);
            final from = (at < 0 ? task.at : at) - 1;
            final passage = passageFor(seg.cards, text, from.clamp(task.from, task.at), (from + 2).clamp(task.from, task.at), maxWords: 320);
            final q = await ai.run((llm) => writer.quickCheck(llm, passage: passage, keySentence: key, seed: task.at));
            if (q != null) local.recalls[task.at] = q;
            changed |= q != null;
        }
        // A reply that failed its checks is not asked for again; one that
        // never ran (the model went away) is.
        if (ai.usable) local.tried.add(_triedKey(task));
        await store.writeBlob(name, encodeLocal(all));
      }
      return changed;
    } catch (e) {
      debugPrint('On-device AI: $e');
      return false;
    } finally {
      _running.remove(key);
    }
  }
}

final localAiSegmenterProvider = Provider<LocalAiSegmenter>(LocalAiSegmenter.new);
