/// A segment map card. Cards reference sentence IDs only; the book text stays
/// on the device and is joined with the map at render time.
library;

enum CardKind { text, chapterTitle, recap, recall, reflect, milestone }

enum SegmentSource { rules, ai }

class HardWord {
  const HardWord({required this.word, required this.sid, this.meaning});

  final String word;
  final String sid;

  /// Meaning in context (AI tiers). Null when only the dictionary is available.
  final String? meaning;

  Map<String, dynamic> toJson() => {'word': word, 'sid': sid, if (meaning != null) 'meaning': meaning};

  factory HardWord.fromJson(Map<String, dynamic> json) => HardWord(
        word: json['word'] as String,
        sid: json['sid'] as String,
        meaning: json['meaning'] as String?,
      );
}

class RecallQuestion {
  const RecallQuestion({required this.question, required this.options, required this.answerIndex});

  final String question;
  final List<String> options;
  final int answerIndex;

  Map<String, dynamic> toJson() => {'question': question, 'options': options, 'answer_index': answerIndex};

  factory RecallQuestion.fromJson(Map<String, dynamic> json) => RecallQuestion(
        question: json['question'] as String,
        options: (json['options'] as List).cast<String>(),
        answerIndex: json['answer_index'] as int,
      );
}

/// A text card produced by a segmenter (rules or AI).
class SegmentCard {
  const SegmentCard({
    required this.chapterIndex,
    required this.startSid,
    required this.endSid,
    required this.sentenceIds,
    required this.wordCount,
    this.title,
    this.hook,
    this.type = 'narrative',
    this.standalone = true,
    this.keySids = const [],
    this.hardWords = const [],
    this.mood,
    this.energy,
  });

  final int chapterIndex;
  final String startSid;
  final String endSid;
  final List<String> sentenceIds;
  final int wordCount;
  final String? title;
  final String? hook;
  final String type;
  final bool standalone;
  final List<String> keySids;
  final List<HardWord> hardWords;

  /// Emotional tone chosen by the AI (soundtrack); null for rule-based cards.
  final String? mood;

  /// 1 (very quiet) – 5 (intense).
  final int? energy;

  Map<String, dynamic> toJson() => {
        'ch': chapterIndex,
        'start_sid': startSid,
        'end_sid': endSid,
        'sids': sentenceIds,
        'words': wordCount,
        if (title != null) 'title': title,
        if (hook != null) 'hook': hook,
        'type': type,
        'standalone': standalone,
        'key_sids': keySids,
        'hard_words': hardWords.map((h) => h.toJson()).toList(),
        if (mood != null) 'mood': mood,
        if (energy != null) 'energy': energy,
      };

  factory SegmentCard.fromJson(Map<String, dynamic> json) => SegmentCard(
        chapterIndex: json['ch'] as int,
        startSid: json['start_sid'] as String,
        endSid: json['end_sid'] as String,
        sentenceIds: (json['sids'] as List).cast<String>(),
        wordCount: json['words'] as int,
        title: json['title'] as String?,
        hook: json['hook'] as String?,
        type: (json['type'] as String?) ?? 'narrative',
        standalone: (json['standalone'] as bool?) ?? true,
        keySids: ((json['key_sids'] as List?) ?? const []).cast<String>(),
        hardWords: ((json['hard_words'] as List?) ?? const [])
            .map((e) => HardWord.fromJson(e as Map<String, dynamic>))
            .toList(),
        mood: json['mood'] as String?,
        energy: (json['energy'] as num?)?.toInt(),
      );
}

/// Segmentation result for one chapter.
class ChapterSegments {
  const ChapterSegments({
    required this.chapterIndex,
    required this.cards,
    required this.source,
    this.recaps = const {},
    this.recalls = const {},
    this.teaser,
  });

  final int chapterIndex;
  final List<SegmentCard> cards;
  final SegmentSource source;

  /// Recap bullets keyed by the index of the card they follow.
  final Map<int, List<String>> recaps;

  /// Recall questions keyed by the index of the card they follow.
  final Map<int, RecallQuestion> recalls;
  final String? teaser;

  Map<String, dynamic> toJson() => {
        'ch': chapterIndex,
        'source': source.name,
        'cards': cards.map((c) => c.toJson()).toList(),
        'recaps': recaps.map((k, v) => MapEntry('$k', v)),
        'recalls': recalls.map((k, v) => MapEntry('$k', v.toJson())),
        if (teaser != null) 'teaser': teaser,
      };

  factory ChapterSegments.fromJson(Map<String, dynamic> json) => ChapterSegments(
        chapterIndex: json['ch'] as int,
        source: SegmentSource.values.byName(json['source'] as String),
        cards: (json['cards'] as List)
            .map((e) => SegmentCard.fromJson(e as Map<String, dynamic>))
            .toList(),
        recaps: ((json['recaps'] as Map?) ?? const {})
            .map((k, v) => MapEntry(int.parse(k as String), (v as List).cast<String>())),
        recalls: ((json['recalls'] as Map?) ?? const {}).map(
            (k, v) => MapEntry(int.parse(k as String), RecallQuestion.fromJson(v as Map<String, dynamic>))),
        teaser: json['teaser'] as String?,
      );
}

/// An item in the reader feed.
class FeedItem {
  const FeedItem({
    required this.kind,
    required this.chapterIndex,
    this.card,
    this.cardIndexInChapter,
    this.cardsInChapter,
    this.recapBullets,
    this.recall,
    this.recallSids,
    this.teaser,
  });

  final CardKind kind;
  final int chapterIndex;
  final SegmentCard? card;
  final int? cardIndexInChapter;
  final int? cardsInChapter;
  final List<String>? recapBullets;
  final RecallQuestion? recall;

  /// For rule-based recall cards: the key sentences to reveal.
  final List<String>? recallSids;
  final String? teaser;

  /// The sentence that anchors this feed item to a reading position.
  String? get anchorSid => card?.startSid;
}
