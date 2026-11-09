import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'store_provider.dart';

/// Highlight tints (UX_DESIGN.md §6.2): amber, green, blue, pink.
const highlightColorCount = 4;

class Highlight {
  const Highlight({
    required this.id,
    required this.bookId,
    required this.bookTitle,
    required this.sid,
    required this.text,
    required this.createdAt,
    this.color = 0,
    this.note,
  });

  final String id;
  final String bookId;
  final String bookTitle;
  final String sid;
  final String text;
  final int color;
  final String? note;
  final DateTime createdAt;

  Highlight copyWith({int? color, String? note}) => Highlight(
        id: id,
        bookId: bookId,
        bookTitle: bookTitle,
        sid: sid,
        text: text,
        createdAt: createdAt,
        color: color ?? this.color,
        note: note ?? this.note,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'book': bookId,
        'title': bookTitle,
        'sid': sid,
        'text': text,
        'color': color,
        'note': note,
        'at': createdAt.toIso8601String(),
      };

  factory Highlight.fromJson(Map<String, dynamic> j) => Highlight(
        id: j['id'] as String,
        bookId: j['book'] as String,
        bookTitle: j['title'] as String,
        sid: j['sid'] as String,
        text: j['text'] as String,
        color: (j['color'] as int?) ?? 0,
        note: j['note'] as String?,
        createdAt: DateTime.parse(j['at'] as String),
      );
}

class SavedCard {
  const SavedCard({
    required this.id,
    required this.bookId,
    required this.bookTitle,
    required this.author,
    required this.chapterTitle,
    required this.startSid,
    required this.text,
    required this.createdAt,
    this.collection = 'Saved',
  });

  final String id;
  final String bookId;
  final String bookTitle;
  final String author;
  final String chapterTitle;
  final String startSid;

  /// Full text snapshot so saved cards work offline and survive book deletion.
  final String text;
  final DateTime createdAt;
  final String collection;

  Map<String, dynamic> toJson() => {
        'id': id,
        'book': bookId,
        'title': bookTitle,
        'author': author,
        'chapter': chapterTitle,
        'sid': startSid,
        'text': text,
        'at': createdAt.toIso8601String(),
        'collection': collection,
      };

  factory SavedCard.fromJson(Map<String, dynamic> j) => SavedCard(
        id: j['id'] as String,
        bookId: j['book'] as String,
        bookTitle: j['title'] as String,
        author: (j['author'] as String?) ?? '',
        chapterTitle: (j['chapter'] as String?) ?? '',
        startSid: j['sid'] as String,
        text: j['text'] as String,
        createdAt: DateTime.parse(j['at'] as String),
        collection: (j['collection'] as String?) ?? 'Saved',
      );
}

/// Leitner-style review intervals in days.
const reviewIntervals = [1, 3, 7, 16, 35, 90];

class WordEntry {
  const WordEntry({
    required this.word,
    required this.meaning,
    required this.sentence,
    required this.bookTitle,
    required this.addedAt,
    required this.dueAt,
    this.box = 0,
  });

  final String word;
  final String meaning;
  final String sentence;
  final String bookTitle;
  final DateTime addedAt;
  final DateTime dueAt;
  final int box;

  WordEntry reviewed({required bool remembered, required DateTime now}) {
    final nextBox = remembered ? (box + 1).clamp(0, reviewIntervals.length - 1) : 0;
    return WordEntry(
      word: word,
      meaning: meaning,
      sentence: sentence,
      bookTitle: bookTitle,
      addedAt: addedAt,
      dueAt: now.add(Duration(days: reviewIntervals[nextBox])),
      box: nextBox,
    );
  }

  Map<String, dynamic> toJson() => {
        'word': word,
        'meaning': meaning,
        'sentence': sentence,
        'title': bookTitle,
        'at': addedAt.toIso8601String(),
        'due': dueAt.toIso8601String(),
        'box': box,
      };

  factory WordEntry.fromJson(Map<String, dynamic> j) => WordEntry(
        word: j['word'] as String,
        meaning: j['meaning'] as String,
        sentence: (j['sentence'] as String?) ?? '',
        bookTitle: (j['title'] as String?) ?? '',
        addedAt: DateTime.parse(j['at'] as String),
        dueAt: DateTime.parse(j['due'] as String),
        box: (j['box'] as int?) ?? 0,
      );
}

class Reflection {
  const Reflection({
    required this.id,
    required this.bookTitle,
    required this.chapterTitle,
    required this.text,
    required this.createdAt,
  });

  final String id;
  final String bookTitle;
  final String chapterTitle;
  final String text;
  final DateTime createdAt;

  Map<String, dynamic> toJson() =>
      {'id': id, 'title': bookTitle, 'chapter': chapterTitle, 'text': text, 'at': createdAt.toIso8601String()};

  factory Reflection.fromJson(Map<String, dynamic> j) => Reflection(
        id: j['id'] as String,
        bookTitle: j['title'] as String,
        chapterTitle: (j['chapter'] as String?) ?? '',
        text: j['text'] as String,
        createdAt: DateTime.parse(j['at'] as String),
      );
}

class NotebookState {
  const NotebookState({
    this.highlights = const [],
    this.saved = const [],
    this.words = const [],
    this.reflections = const [],
    this.liked = const {},
  });

  final List<Highlight> highlights;
  final List<SavedCard> saved;
  final List<WordEntry> words;
  final List<Reflection> reflections;

  /// Liked card start sIDs, keyed `bookId|sid` (double-tap).
  final Set<String> liked;

  NotebookState copyWith({
    List<Highlight>? highlights,
    List<SavedCard>? saved,
    List<WordEntry>? words,
    List<Reflection>? reflections,
    Set<String>? liked,
  }) =>
      NotebookState(
        highlights: highlights ?? this.highlights,
        saved: saved ?? this.saved,
        words: words ?? this.words,
        reflections: reflections ?? this.reflections,
        liked: liked ?? this.liked,
      );

  Map<String, dynamic> toJson() => {
        'highlights': highlights.map((e) => e.toJson()).toList(),
        'saved': saved.map((e) => e.toJson()).toList(),
        'words': words.map((e) => e.toJson()).toList(),
        'reflections': reflections.map((e) => e.toJson()).toList(),
        'liked': liked.toList(),
      };

  factory NotebookState.fromJson(Map<String, dynamic> j) {
    List<T> list<T>(String key, T Function(Map<String, dynamic>) f) =>
        ((j[key] as List?) ?? const []).map((e) => f(e as Map<String, dynamic>)).toList();
    return NotebookState(
      highlights: list('highlights', Highlight.fromJson),
      saved: list('saved', SavedCard.fromJson),
      words: list('words', WordEntry.fromJson),
      reflections: list('reflections', Reflection.fromJson),
      liked: ((j['liked'] as List?) ?? const []).cast<String>().toSet(),
    );
  }

  bool isSaved(String bookId, String startSid) => saved.any((s) => s.bookId == bookId && s.startSid == startSid);

  Highlight? highlightFor(String bookId, String sid) =>
      highlights.where((h) => h.bookId == bookId && h.sid == sid).firstOrNull;

  bool hasWord(String word) => words.any((w) => w.word.toLowerCase() == word.toLowerCase());

  List<WordEntry> dueWords(DateTime now) => words.where((w) => !w.dueAt.isAfter(now)).toList();
}

String _id() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);

class NotebookNotifier extends Notifier<NotebookState> {
  @override
  NotebookState build() {
    final json = ref.read(storeProvider).doc('notebook');
    return json == null ? const NotebookState() : NotebookState.fromJson(json);
  }

  void _set(NotebookState next) {
    state = next;
    ref.read(storeProvider).saveDoc('notebook', next.toJson());
  }

  /// Toggles a highlight on a sentence; returns the new highlight or null when removed.
  Highlight? toggleHighlight({
    required String bookId,
    required String bookTitle,
    required String sid,
    required String text,
    int color = 0,
  }) {
    final existing = state.highlightFor(bookId, sid);
    if (existing != null) {
      _set(state.copyWith(highlights: state.highlights.where((h) => h.id != existing.id).toList()));
      return null;
    }
    final h = Highlight(
        id: _id(), bookId: bookId, bookTitle: bookTitle, sid: sid, text: text, color: color, createdAt: DateTime.now());
    _set(state.copyWith(highlights: [h, ...state.highlights]));
    return h;
  }

  void updateHighlight(Highlight h) =>
      _set(state.copyWith(highlights: [for (final x in state.highlights) x.id == h.id ? h : x]));

  void removeHighlight(String id) =>
      _set(state.copyWith(highlights: state.highlights.where((h) => h.id != id).toList()));

  /// Toggles a saved card; returns true when the card is now saved.
  bool toggleSaved(SavedCard card) {
    if (state.isSaved(card.bookId, card.startSid)) {
      _set(state.copyWith(
          saved: state.saved.where((s) => !(s.bookId == card.bookId && s.startSid == card.startSid)).toList()));
      return false;
    }
    _set(state.copyWith(saved: [card, ...state.saved]));
    return true;
  }

  void removeSaved(String id) => _set(state.copyWith(saved: state.saved.where((s) => s.id != id).toList()));

  /// Toggles a like; returns true when liked.
  bool toggleLike(String bookId, String sid) {
    final key = '$bookId|$sid';
    final liked = {...state.liked};
    final added = liked.add(key);
    if (!added) liked.remove(key);
    _set(state.copyWith(liked: liked));
    return added;
  }

  void like(String bookId, String sid) {
    final key = '$bookId|$sid';
    if (state.liked.contains(key)) return;
    _set(state.copyWith(liked: {...state.liked, key}));
  }

  void addWord({required String word, required String meaning, required String sentence, required String bookTitle}) {
    if (state.hasWord(word)) return;
    final now = DateTime.now();
    _set(state.copyWith(words: [
      WordEntry(
          word: word,
          meaning: meaning,
          sentence: sentence,
          bookTitle: bookTitle,
          addedAt: now,
          dueAt: now.add(const Duration(days: 1))),
      ...state.words,
    ]));
  }

  void reviewWord(String word, {required bool remembered}) {
    final now = DateTime.now();
    _set(state.copyWith(words: [
      for (final w in state.words)
        w.word == word ? w.reviewed(remembered: remembered, now: now) : w,
    ]));
  }

  void removeWord(String word) => _set(state.copyWith(words: state.words.where((w) => w.word != word).toList()));

  void addReflection({required String bookTitle, required String chapterTitle, required String text}) {
    if (text.trim().isEmpty) return;
    _set(state.copyWith(reflections: [
      Reflection(id: _id(), bookTitle: bookTitle, chapterTitle: chapterTitle, text: text.trim(), createdAt: DateTime.now()),
      ...state.reflections,
    ]));
  }

  String newId() => _id();
}

final notebookProvider = NotifierProvider<NotebookNotifier, NotebookState>(NotebookNotifier.new);

/// Exports the notebook to Markdown (DESIGN.md §2.7).
String notebookToMarkdown(NotebookState n) {
  final b = StringBuffer('# My BookReel notebook\n');
  final byBook = <String, List<Highlight>>{};
  for (final h in n.highlights) {
    byBook.putIfAbsent(h.bookTitle, () => []).add(h);
  }
  if (byBook.isNotEmpty) b.writeln('\n## Highlights');
  for (final e in byBook.entries) {
    b.writeln('\n### ${e.key}\n');
    for (final h in e.value) {
      b.writeln('> ${h.text}');
      if (h.note != null && h.note!.isNotEmpty) b.writeln('\n${h.note}');
      b.writeln();
    }
  }
  if (n.saved.isNotEmpty) {
    b.writeln('\n## Saved cards\n');
    for (final s in n.saved) {
      b.writeln('> ${s.text}\n>\n> — ${s.bookTitle}, ${s.chapterTitle}\n');
    }
  }
  if (n.reflections.isNotEmpty) {
    b.writeln('\n## Reflections\n');
    for (final r in n.reflections) {
      b.writeln('- **${r.bookTitle} · ${r.chapterTitle}:** ${r.text}');
    }
  }
  if (n.words.isNotEmpty) {
    b.writeln('\n## Words\n');
    for (final w in n.words) {
      b.writeln('- **${w.word}**: ${w.meaning}');
    }
  }
  return b.toString();
}
