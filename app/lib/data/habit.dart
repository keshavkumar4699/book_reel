import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/habit/habit_engine.dart';
import 'ai_client.dart' show bookreelApi;
import 'api_client.dart';
import 'settings_provider.dart';
import 'store_provider.dart';

class HabitState {
  const HabitState({
    this.stats = const {},
    this.streak = const StreakState(),
    this.wpm = defaultWpm,
    this.booksFinished = 0,
    this.celebratedMilestone = 0,
  });

  final Map<String, DailyStat> stats;
  final StreakState streak;
  final double wpm;
  final int booksFinished;
  final int celebratedMilestone;

  DailyStat today(DateTime now) => stats[dateKey(now)] ?? const DailyStat();

  int get totalVerifiedCards => stats.values.fold(0, (s, d) => s + d.verifiedCards);
  double get totalMinutes => stats.values.fold(0.0, (s, d) => s + d.minutes);
  int get totalWords => stats.values.fold(0, (s, d) => s + d.words);

  HabitState copyWith({
    Map<String, DailyStat>? stats,
    StreakState? streak,
    double? wpm,
    int? booksFinished,
    int? celebratedMilestone,
  }) =>
      HabitState(
        stats: stats ?? this.stats,
        streak: streak ?? this.streak,
        wpm: wpm ?? this.wpm,
        booksFinished: booksFinished ?? this.booksFinished,
        celebratedMilestone: celebratedMilestone ?? this.celebratedMilestone,
      );

  Map<String, dynamic> toJson() => {
        'stats': stats.map((k, v) => MapEntry(k, v.toJson())),
        'streak': streak.toJson(),
        'wpm': wpm,
        'booksFinished': booksFinished,
        'celebrated': celebratedMilestone,
      };

  factory HabitState.fromJson(Map<String, dynamic> j) => HabitState(
        stats: ((j['stats'] as Map?) ?? const {})
            .map((k, v) => MapEntry(k as String, DailyStat.fromJson(v as Map<String, dynamic>))),
        streak: j['streak'] == null ? const StreakState() : StreakState.fromJson(j['streak'] as Map<String, dynamic>),
        // A speed learnt before the careful-reading ceiling came in is brought under it.
        wpm: ((j['wpm'] as num?) ?? defaultWpm).toDouble().clamp(minWpm, maxWpm).toDouble(),
        booksFinished: (j['booksFinished'] as int?) ?? 0,
        celebratedMilestone: (j['celebrated'] as int?) ?? 0,
      );
}

class CardRecord {
  const CardRecord({required this.verified, required this.goalJustMet, required this.streak, this.milestone, this.minutes = 0});

  /// Really read: it counts toward everything. A skimmed card counts toward nothing.
  final bool verified;

  /// Reading minutes credited (0 when skimmed).
  final double minutes;

  /// True only on the card that crosses today's goal.
  final bool goalJustMet;
  final int streak;

  /// Set when this goal completion reaches a new streak milestone.
  final int? milestone;
}

class HabitNotifier extends Notifier<HabitState> {
  /// Injectable clock for tests.
  DateTime Function() clock = DateTime.now;

  @override
  HabitState build() {
    final store = ref.read(storeProvider);
    // A build without a server can never send its reading events: drop any
    // queued by earlier versions, which saved them all again on every card.
    if (bookreelApi.isEmpty && ((store.doc('outbox')?['events'] as List?)?.isNotEmpty ?? false)) {
      store.saveDoc('outbox', {'events': <Object>[]});
    }
    final json = store.doc('habit');
    return json == null ? const HabitState() : HabitState.fromJson(json);
  }

  void _set(HabitState next) {
    state = next;
    ref.read(storeProvider).saveDoc('habit', next.toJson());
  }

  StreakEngine get _engine => StreakEngine(ref.read(settingsProvider).goal);

  /// Records time spent on a text card and updates goal/streak. With a
  /// [bookId] and [cardRef] the raw event is also queued for upload when
  /// online features are on, so the server can verify it for leagues (see
  /// SyncService).
  CardRecord recordCard({required int words, required int dwellMs, String? bookId, String? cardRef}) {
    final now = clock();
    if (bookId != null && cardRef != null && ref.read(apiProvider).enabled) _enqueue(bookId, cardRef, words, dwellMs, now);
    final goal = ref.read(settingsProvider).goal;
    final result = evaluateDwell(words: words, dwellMs: dwellMs, wpm: state.wpm);
    final key = dateKey(now);
    final before = state.today(now);
    final after = before.add(verified: result.verified, minutes: result.minutes, words: words);
    final justMet = !before.meets(goal) && after.meets(goal);
    var streak = state.streak;
    int? milestone;
    var celebrated = state.celebratedMilestone;
    if (justMet) {
      streak = _engine.recordGoalMet(streak, now);
      final reached = streakMilestones.where((m) => m <= streak.current && m > celebrated).lastOrNull;
      if (reached != null) {
        milestone = reached;
        celebrated = reached;
      }
      if (streak.current < celebrated) celebrated = 0; // streak restarted
    }
    _set(state.copyWith(
      stats: {...state.stats, key: after},
      streak: streak,
      wpm: result.updatedWpm,
      celebratedMilestone: celebrated,
    ));
    return CardRecord(verified: result.verified, goalJustMet: justMet, streak: streak.current, milestone: milestone, minutes: result.minutes);
  }

  static const _outboxMax = 1500;

  void _enqueue(String bookId, String cardRef, int words, int dwellMs, DateTime at) {
    final store = ref.read(storeProvider);
    final events = [...((store.doc('outbox')?['events'] as List?) ?? const [])];
    events.add({
      'book_id': bookId.length > 80 ? bookId.substring(0, 80) : bookId,
      'card_ref': cardRef,
      'words': words.clamp(0, 2000),
      'dwell_ms': dwellMs.clamp(0, 3600000),
      'ts': at.toUtc().toIso8601String(),
    });
    // Keep the queue bounded (it's saved whole on every card) if the phone
    // stays offline for a long time; the server credits recent reading anyway.
    store.saveDoc('outbox', {'events': events.length > _outboxMax ? events.sublist(events.length - _outboxMax) : events});
  }

  void bookFinished() => _set(state.copyWith(booksFinished: state.booksFinished + 1));

  int displayStreak() {
    final s = ref.read(settingsProvider);
    if (s.goalMode == GoalMode.weekly) return _engine.weeklyStreak(state.stats, clock());
    return _engine.displayStreak(state.streak, clock());
  }

  int freezesLeft() => _engine.refill(state.streak, clock()).freezesLeft;

  /// Active days in the current ISO week (for weekly mode).
  int activeDaysThisWeek() {
    final goal = ref.read(settingsProvider).goal;
    final start = parseDateKey(weekKey(clock()));
    var n = 0;
    for (var d = 0; d < 7; d++) {
      final stat = state.stats[dateKey(DateTime(start.year, start.month, start.day + d))];
      if (stat != null && stat.meets(goal)) n++;
    }
    return n;
  }
}

final habitProvider = NotifierProvider<HabitNotifier, HabitState>(HabitNotifier.new);
