import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'store_provider.dart';

/// One reading session for the Today feed (Cloro plan §10): what you read,
/// for how long, how far you got and how you felt.
class ReadingSession {
  const ReadingSession({
    required this.id,
    required this.bookId,
    required this.title,
    required this.author,
    required this.startedAt,
    required this.endedAt,
    this.minutes = 0,
    this.cards = 0,
    this.progress = 0,
    this.mood,
    this.quote,
    this.uploaded = false,
  });

  /// Also the server's `client_id`, so re-uploads update one card.
  final String id;
  final String bookId;
  final String title;
  final String author;
  final DateTime startedAt;
  final DateTime endedAt;
  final double minutes;
  final int cards;

  /// How far into the book, 0–1.
  final double progress;

  /// The mood's name (Mood.name), when one was set for this session.
  final String? mood;

  /// A line saved during the session (public-domain books only).
  final String? quote;
  final bool uploaded;

  ReadingSession copyWith({
    DateTime? endedAt,
    double? minutes,
    int? cards,
    double? progress,
    String? mood,
    String? quote,
    bool? uploaded,
  }) =>
      ReadingSession(
        id: id,
        bookId: bookId,
        title: title,
        author: author,
        startedAt: startedAt,
        endedAt: endedAt ?? this.endedAt,
        minutes: minutes ?? this.minutes,
        cards: cards ?? this.cards,
        progress: progress ?? this.progress,
        mood: mood ?? this.mood,
        quote: quote ?? this.quote,
        uploaded: uploaded ?? this.uploaded,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'bookId': bookId,
        'title': title,
        'author': author,
        'startedAt': startedAt.toIso8601String(),
        'endedAt': endedAt.toIso8601String(),
        'minutes': minutes,
        'cards': cards,
        'progress': progress,
        'mood': mood,
        'quote': quote,
        'uploaded': uploaded,
      };

  static ReadingSession? fromJson(Object? j) {
    if (j is! Map) return null;
    final started = DateTime.tryParse('${j['startedAt']}');
    final ended = DateTime.tryParse('${j['endedAt']}');
    if (started == null || ended == null || j['id'] is! String) return null;
    return ReadingSession(
      id: j['id'] as String,
      bookId: '${j['bookId'] ?? ''}',
      title: '${j['title'] ?? ''}',
      author: '${j['author'] ?? ''}',
      startedAt: started,
      endedAt: ended,
      minutes: (j['minutes'] as num?)?.toDouble() ?? 0,
      cards: (j['cards'] as num?)?.toInt() ?? 0,
      progress: (j['progress'] as num?)?.toDouble() ?? 0,
      mood: j['mood'] as String?,
      quote: j['quote'] as String?,
      uploaded: j['uploaded'] == true,
    );
  }

  /// What the feed gets: the stats, the book's title and author, the mood and
  /// the saved line. Nothing else from the book.
  Map<String, dynamic> toUpload() => {
        'client_id': id,
        'started_at': startedAt.toUtc().toIso8601String(),
        'minutes': math.min(600, (minutes * 10).round() / 10),
        'cards': math.min(2000, cards),
        'book': {'title': _cut(title, 200), 'author': _cut(author, 120)},
        'progress': progress.clamp(0.0, 1.0),
        'mood': ?mood,
        'quote': ?quote,
      };

  /// Worth showing: a few cards or a minute of reading.
  bool get worthSharing => cards > 0 || minutes >= 1;
}

String _cut(String s, int max) => s.length <= max ? s : s.substring(0, max);

/// A line of at most 280 characters, cut at a word with "…".
String sessionQuote(String text) {
  final t = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.length <= 280) return t;
  final cut = t.substring(0, 279);
  final space = cut.lastIndexOf(' ');
  return '${(space > 200 ? cut.substring(0, space) : cut).trimRight()}…';
}

/// Your reading sessions, newest last. Built from the reader's card records:
/// cards read in the same book within 30 minutes of each other are one
/// session. Today shows them at once (offline too), and sync uploads them to
/// the feed of readers who follow you.
class SessionLog extends Notifier<List<ReadingSession>> {
  /// Injectable clock for tests.
  DateTime Function() clock = DateTime.now;

  static const gap = Duration(minutes: 30);
  static const _keep = 200;
  static final _random = math.Random();

  @override
  List<ReadingSession> build() {
    final items = (ref.read(storeProvider).doc('sessions')?['items'] as List?) ?? const [];
    return [for (final j in items) ?ReadingSession.fromJson(j)];
  }

  void _set(List<ReadingSession> next) {
    state = next.length > _keep ? next.sublist(next.length - _keep) : next;
    ref.read(storeProvider).saveDoc('sessions', {'items': [for (final s in state) s.toJson()]});
  }

  ReadingSession? _open(String bookId, DateTime now) {
    final last = state.lastOrNull;
    return last != null && last.bookId == bookId && now.difference(last.endedAt) <= gap ? last : null;
  }

  /// A card read: [dwellMs] on it, the book now at [progress], in [mood].
  void record({
    required String bookId,
    required String title,
    required String author,
    required int dwellMs,
    required double progress,
    String? mood,
  }) {
    final now = clock();
    final open = _open(bookId, now);
    final minutes = math.max(0, dwellMs) / 60000;
    if (open != null) {
      _set([
        ...state.sublist(0, state.length - 1),
        open.copyWith(
          endedAt: now,
          minutes: open.minutes + minutes,
          cards: open.cards + 1,
          progress: math.max(open.progress, progress),
          mood: mood,
          uploaded: false,
        ),
      ]);
    } else {
      final id = '${now.microsecondsSinceEpoch.toRadixString(36)}${_random.nextInt(1 << 30).toRadixString(36)}';
      _set([
        ...state,
        ReadingSession(
          id: 's$id',
          bookId: bookId,
          title: title,
          author: author,
          startedAt: now.subtract(Duration(milliseconds: math.max(0, dwellMs))),
          endedAt: now,
          minutes: minutes,
          cards: 1,
          progress: progress,
          mood: mood,
        ),
      ]);
    }
  }

  /// A line saved while reading: it shows on the session's card.
  void quote(String bookId, String text) {
    final open = _open(bookId, clock());
    if (open == null || text.trim().isEmpty) return;
    _set([...state.sublist(0, state.length - 1), open.copyWith(quote: sessionQuote(text), uploaded: false)]);
  }

  /// Sessions the feed hasn't got in their latest form.
  List<ReadingSession> get pending => [for (final s in state) if (!s.uploaded && s.worthSharing) s];

  /// [sent] reached the server; unless the session grew meanwhile, it's done.
  void markUploaded(ReadingSession sent) {
    final i = state.indexWhere((s) => s.id == sent.id);
    if (i < 0) return;
    final now = state[i];
    if (now.cards != sent.cards || now.quote != sent.quote || now.minutes != sent.minutes) return;
    _set([...state.sublist(0, i), now.copyWith(uploaded: true), ...state.sublist(i + 1)]);
  }
}

final sessionLogProvider = NotifierProvider<SessionLog, List<ReadingSession>>(SessionLog.new);
