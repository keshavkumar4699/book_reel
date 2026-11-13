/// Content model shared by the parser, segmenter and reader.
///
/// Sentence IDs (`c{chapter}.b{block}.s{sentence}`) are the single position
/// model: reading position, highlights, saved cards and AI segment maps all
/// point at sentence IDs, so re-segmenting a book never loses the user's place.
library;

import 'front_matter.dart';

enum BlockType { heading, paragraph, quote, list, dialogue, preformatted }

enum BookFormat { epub, pdf, text }

class Sentence {
  const Sentence({required this.id, required this.text});

  final String id;
  final String text;

  int get wordCount => countWords(text);

  Map<String, dynamic> toJson() => {'id': id, 't': text};

  factory Sentence.fromJson(Map<String, dynamic> json) =>
      Sentence(id: json['id'] as String, text: json['t'] as String);
}

class Block {
  const Block({required this.index, required this.type, required this.sentences});

  final int index;
  final BlockType type;
  final List<Sentence> sentences;

  String get text => sentences.map((s) => s.text).join(' ');

  Map<String, dynamic> toJson() => {
        'i': index,
        'type': type.name,
        's': sentences.map((s) => s.toJson()).toList(),
      };

  factory Block.fromJson(Map<String, dynamic> json) => Block(
        index: json['i'] as int,
        type: BlockType.values.byName(json['type'] as String),
        sentences: (json['s'] as List)
            .map((e) => Sentence.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class Chapter {
  const Chapter({required this.index, required this.title, required this.blocks});

  final int index;
  final String title;
  final List<Block> blocks;

  Iterable<Sentence> get sentences => blocks.expand((b) => b.sentences);

  int get wordCount => blocks.fold(0, (sum, b) => sum + b.sentences.fold(0, (s, x) => s + x.wordCount));

  Map<String, dynamic> toJson() => {
        'i': index,
        'title': title,
        'b': blocks.map((b) => b.toJson()).toList(),
      };

  factory Chapter.fromJson(Map<String, dynamic> json) => Chapter(
        index: json['i'] as int,
        title: json['title'] as String,
        blocks: (json['b'] as List)
            .map((e) => Block.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class BookContent {
  const BookContent({
    required this.title,
    required this.author,
    required this.chapters,
    this.language = 'en',
    this.bodyStart = 0,
  });

  final String title;
  final String author;
  final String language;
  final List<Chapter> chapters;

  /// The chapter where the book's own text begins (after the title page,
  /// copyright and contents): a new book opens here. See front_matter.dart.
  final int bodyStart;

  int get wordCount => chapters.fold(0, (sum, c) => sum + c.wordCount);

  Map<String, dynamic> toJson() => {
        'title': title,
        'author': author,
        'lang': language,
        'start': bodyStart,
        'chapters': chapters.map((c) => c.toJson()).toList(),
      };

  factory BookContent.fromJson(Map<String, dynamic> json) {
    final chapters = (json['chapters'] as List).map((e) => Chapter.fromJson(e as Map<String, dynamic>)).toList();
    return BookContent(
      title: json['title'] as String,
      author: json['author'] as String,
      language: (json['lang'] as String?) ?? 'en',
      chapters: chapters,
      // Books saved before this existed: work it out now.
      bodyStart: (json['start'] as num?)?.toInt() ?? findBodyStart(chapters),
    );
  }
}

/// Library entry. [id] is the SHA-256 content hash of the imported file.
class BookMeta {
  const BookMeta({
    required this.id,
    required this.title,
    required this.author,
    required this.format,
    required this.addedAt,
    required this.wordCount,
    required this.chapterCount,
    this.isPublicDomain = false,
    this.coverPath,
    this.lastReadAt,
    this.positionSid,
    this.positionOffset = 0,
    this.progress = 0,
    this.finishedAt,
    this.subjects = const [],
    this.voice,
    this.voiceSource,
  });

  final String id;
  final String title;
  final String author;
  final BookFormat format;
  final DateTime addedAt;
  final int wordCount;
  final int chapterCount;
  final bool isPublicDomain;
  final String? coverPath;
  final DateTime? lastReadAt;
  final String? positionSid;

  /// Character offset inside [positionSid], when a long sentence continues
  /// over several reels and the reader stopped part-way through it.
  final int positionOffset;

  /// 0.0 – 1.0, by words read before the current position.
  final double progress;
  final DateTime? finishedAt;

  /// Genre tags from the file's metadata (`dc:subject`).
  final List<String> subjects;

  /// Typographic voice of the book (`BookVoice` name), and who chose it:
  /// "rules" (on-device) or "ai".
  final String? voice;
  final String? voiceSource;

  BookMeta copyWith({
    DateTime? lastReadAt,
    String? positionSid,
    int? positionOffset,
    double? progress,
    DateTime? finishedAt,
    String? coverPath,
    String? voice,
    String? voiceSource,
  }) =>
      BookMeta(
        id: id,
        title: title,
        author: author,
        format: format,
        addedAt: addedAt,
        wordCount: wordCount,
        chapterCount: chapterCount,
        isPublicDomain: isPublicDomain,
        coverPath: coverPath ?? this.coverPath,
        lastReadAt: lastReadAt ?? this.lastReadAt,
        positionSid: positionSid ?? this.positionSid,
        positionOffset: positionOffset ?? this.positionOffset,
        progress: progress ?? this.progress,
        finishedAt: finishedAt ?? this.finishedAt,
        subjects: subjects,
        voice: voice ?? this.voice,
        voiceSource: voiceSource ?? this.voiceSource,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'author': author,
        'format': format.name,
        'addedAt': addedAt.toIso8601String(),
        'wordCount': wordCount,
        'chapterCount': chapterCount,
        'pd': isPublicDomain,
        'cover': coverPath,
        'lastReadAt': lastReadAt?.toIso8601String(),
        'pos': positionSid,
        if (positionOffset > 0) 'posOffset': positionOffset,
        'progress': progress,
        'finishedAt': finishedAt?.toIso8601String(),
        if (subjects.isNotEmpty) 'subjects': subjects,
        if (voice != null) 'voice': voice,
        if (voiceSource != null) 'voiceSource': voiceSource,
      };

  factory BookMeta.fromJson(Map<String, dynamic> json) => BookMeta(
        id: json['id'] as String,
        title: json['title'] as String,
        author: json['author'] as String,
        format: BookFormat.values.byName(json['format'] as String),
        addedAt: DateTime.parse(json['addedAt'] as String),
        wordCount: json['wordCount'] as int,
        chapterCount: json['chapterCount'] as int,
        isPublicDomain: (json['pd'] as bool?) ?? false,
        coverPath: json['cover'] as String?,
        lastReadAt: json['lastReadAt'] == null ? null : DateTime.parse(json['lastReadAt'] as String),
        positionSid: json['pos'] as String?,
        positionOffset: ((json['posOffset'] as num?) ?? 0).toInt(),
        progress: ((json['progress'] as num?) ?? 0).toDouble(),
        finishedAt: json['finishedAt'] == null ? null : DateTime.parse(json['finishedAt'] as String),
        subjects: ((json['subjects'] as List?) ?? const []).cast<String>(),
        voice: json['voice'] as String?,
        voiceSource: json['voiceSource'] as String?,
      );
}

final RegExp _wordRe = RegExp(r"[\p{L}\p{N}][\p{L}\p{N}'’\-]*", unicode: true);

int countWords(String text) => _wordRe.allMatches(text).length;

/// Parses a sentence ID into (chapter, block, sentence) indices.
({int chapter, int block, int sentence})? parseSid(String sid) {
  final m = RegExp(r'^c(\d+)\.b(\d+)\.s(\d+)$').firstMatch(sid);
  if (m == null) return null;
  return (
    chapter: int.parse(m.group(1)!),
    block: int.parse(m.group(2)!),
    sentence: int.parse(m.group(3)!),
  );
}

String makeSid(int chapter, int block, int sentence) => 'c$chapter.b$block.s$sentence';

/// Reading order of two sentence IDs (negative when [a] comes first).
int compareSids(String a, String b) {
  final x = parseSid(a), y = parseSid(b);
  if (x == null || y == null) return a.compareTo(b);
  if (x.chapter != y.chapter) return x.chapter - y.chapter;
  if (x.block != y.block) return x.block - y.block;
  return x.sentence - y.sentence;
}
