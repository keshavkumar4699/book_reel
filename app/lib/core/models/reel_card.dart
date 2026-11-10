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

/// A phrase the AI chose to show large (lyric-style typography).
class Emphasis {
  const Emphasis({required this.sid, required this.text, required this.level});

  final String sid;

  /// Exact substring of the sentence.
  final String text;

  /// 2 = large, 3 = hero.
  final int level;

  Map<String, dynamic> toJson() => {'sid': sid, 'text': text, 'level': level};

  factory Emphasis.fromJson(Map<String, dynamic> j) =>
      Emphasis(sid: j['sid'] as String, text: j['text'] as String, level: (j['level'] as num).toInt());
}

/// The background scene from a given card onwards.
class SceneCue {
  const SceneCue({required this.atCard, required this.scene});
  final int atCard;
  final String scene;

  Map<String, dynamic> toJson() => {'at_card': atCard, 'scene': scene};
  factory SceneCue.fromJson(Map<String, dynamic> j) => SceneCue(atCard: (j['at_card'] as num).toInt(), scene: j['scene'] as String);
}

/// A film-score style music cue chosen by the AI for part of a chapter.
class MusicCue {
  const MusicCue({required this.atCard, required this.mood, required this.energy, this.description = ''});
  final int atCard;
  final String mood;
  final int energy;
  final String description;

  Map<String, dynamic> toJson() => {'at_card': atCard, 'mood': mood, 'energy': energy, 'description': description};
  factory MusicCue.fromJson(Map<String, dynamic> j) => MusicCue(
        atCard: (j['at_card'] as num).toInt(),
        mood: j['mood'] as String,
        energy: (j['energy'] as num).toInt(),
        description: (j['description'] as String?) ?? '',
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
    this.emphasis = const [],
    this.layout,
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

  /// AI-chosen phrases to show large; empty for rule-based cards.
  final List<Emphasis> emphasis;

  /// "centered", "left" or "staggered"; null lets the app decide.
  final String? layout;

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
        if (emphasis.isNotEmpty) 'emphasis': emphasis.map((e) => e.toJson()).toList(),
        if (layout != null) 'layout': layout,
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
        emphasis: ((json['emphasis'] as List?) ?? const [])
            .map((e) => Emphasis.fromJson(e as Map<String, dynamic>))
            .toList(),
        layout: json['layout'] as String?,
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
    this.scene,
    this.sceneCues = const [],
    this.musicCues = const [],
  });

  final int chapterIndex;
  final List<SegmentCard> cards;
  final SegmentSource source;

  /// Recap bullets keyed by the index of the card they follow.
  final Map<int, List<String>> recaps;

  /// Recall questions keyed by the index of the card they follow.
  final Map<int, RecallQuestion> recalls;
  final String? teaser;

  /// AI-chosen default background for the chapter.
  final String? scene;
  final List<SceneCue> sceneCues;

  /// AI soundtrack plan for the chapter (paid tiers).
  final List<MusicCue> musicCues;

  /// Scene for card [i]: the last cue at or before it, else the chapter scene.
  String? sceneAt(int i) {
    String? s = scene;
    for (final c in sceneCues) {
      if (c.atCard <= i) s = c.scene;
    }
    return s;
  }

  Map<String, dynamic> toJson() => {
        'ch': chapterIndex,
        'source': source.name,
        'cards': cards.map((c) => c.toJson()).toList(),
        'recaps': recaps.map((k, v) => MapEntry('$k', v)),
        'recalls': recalls.map((k, v) => MapEntry('$k', v.toJson())),
        if (teaser != null) 'teaser': teaser,
        if (scene != null) 'scene': scene,
        'scene_cues': sceneCues.map((c) => c.toJson()).toList(),
        'music_cues': musicCues.map((c) => c.toJson()).toList(),
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
        scene: json['scene'] as String?,
        sceneCues: ((json['scene_cues'] as List?) ?? const [])
            .map((e) => SceneCue.fromJson(e as Map<String, dynamic>))
            .toList(),
        musicCues: ((json['music_cues'] as List?) ?? const [])
            .map((e) => MusicCue.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// An item in the reader feed.
///
/// A text card can be shown as more than one reel: its spotlight line (the
/// hero phrase, large) gets a reel of its own, and text too long to sit
/// comfortably on one screen continues on the next reel. Big and small type
/// never share a screen, and text never fills it. [sids] and [lines] say what
/// this reel shows; reading credit stays per card.
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
    this.sids,
    this.lines,
    this.lineSids,
    this.anchor,
    this.words,
    this.spotlight = false,
    this.lastPart = true,
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

  /// Sentences this reel is laid out from when the card is split around a
  /// spotlight; null = all of the card's sentences.
  final List<String>? sids;

  /// When the laid-out text continues over several reels: the range of
  /// display lines (`piecesForCard` of [layoutSids]) on this one.
  final ({int from, int to})? lines;

  /// The sentences those lines belong to (some may continue on the next reel).
  final List<String>? lineSids;

  /// For a continued reel: the first sentence that starts on it (or the
  /// sentence it continues, when none does).
  final String? anchor;

  /// Words on this reel when it shows only part of its card.
  final int? words;

  /// This reel shows the card's spotlight line.
  final bool spotlight;

  /// The last reel of its card (reading credit is recorded once per card).
  final bool lastPart;

  /// Sentences the reel's lines are built from.
  List<String> get layoutSids => sids ?? card?.sentenceIds ?? const [];

  /// Sentences that appear on this reel.
  List<String> get shownSids => lineSids ?? layoutSids;

  /// True when this reel shows only part of its card.
  bool get isPart => sids != null || lines != null;

  /// The sentence that anchors this reel to a reading position, and keys its
  /// like and save.
  String? get anchorSid => anchor ?? (shownSids.isEmpty ? card?.startSid : shownSids.first);
}
