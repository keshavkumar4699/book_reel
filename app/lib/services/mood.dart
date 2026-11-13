import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api_client.dart';
import '../data/settings.dart';
import '../data/settings_provider.dart';
import '../data/store_provider.dart';
import 'on_device_ai.dart';

/// Mood (Cloro plan §8): while learning, Cloro asks "How are you feeling?"
/// when you open a book (at most every 3 hours) and opens it in that mood's
/// scene. Once it has learnt your habit, Google's Gemma predicts the mood that
/// suits you right now (on the phone when Gemma is downloaded, otherwise on
/// the server), with your own habit as the fallback; a check-in comes about
/// once a week, and the "· change" chip corrects a wrong guess.
///
/// Only the mood log is used (when, mood, minutes read): no book text.

enum Mood {
  calm('Calm', '😌', day: Vibe.meadow, night: Vibe.night),
  cozy('Cozy', '☕', day: Vibe.snow, night: Vibe.cafe),
  focused('Focused', '🎯', day: Vibe.paper, night: Vibe.paper),
  energised('Energised', '⚡', day: Vibe.ocean, night: Vibe.city),
  dreamy('Dreamy', '💭', day: Vibe.forest, night: Vibe.night),
  reflective('Reflective', '🌧️', day: Vibe.forest, night: Vibe.rain),
  restless('Restless', '🌀', day: Vibe.snow, night: Vibe.city);

  const Mood(this.label, this.emoji, {required this.day, required this.night});

  final String label;
  final String emoji;

  /// The scene for this mood by day and by night.
  final Vibe day;
  final Vibe night;

  /// Day or night by the clock, unless the app is set to Light or Dark.
  Vibe sceneAt(DateTime at, AppAppearance appearance) => switch (appearance) {
        AppAppearance.light => day,
        AppAppearance.dark => night,
        AppAppearance.system => isDaytime(at) ? day : night,
      };

  static Mood? byName(String? name) {
    final n = (name ?? '').trim().toLowerCase();
    final alias = switch (n) { 'energized' => 'energised', 'cosy' => 'cozy', _ => n };
    return Mood.values.where((m) => m.name == alias).firstOrNull;
  }
}

/// 7:00 to 19:00.
bool isDaytime(DateTime at) => at.hour >= 7 && at.hour < 19;

/// Morning 5–12, afternoon 12–17, evening 17–22, night 22–5.
String slotOf(int hour) => hour >= 5 && hour < 12
    ? 'morning'
    : hour >= 12 && hour < 17
        ? 'afternoon'
        : hour >= 17 && hour < 22
            ? 'evening'
            : 'night';

/// The day and time slot, e.g. "2026-11-13 evening" (a night after midnight
/// belongs to the evening before).
String slotKey(DateTime at) {
  final day = at.hour < 5 ? at.subtract(const Duration(hours: 5)) : at;
  final d = '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
  return '$d ${slotOf(at.hour)}';
}

enum MoodSource { asked, corrected, predicted }

/// Who predicted a mood.
enum MoodBy { phone, server, habit }

class MoodEntry {
  const MoodEntry({required this.at, required this.mood, required this.source, this.minutes = 0});

  final DateTime at;
  final Mood mood;
  final MoodSource source;

  /// Minutes read in the session that followed.
  final double minutes;

  bool get answered => source != MoodSource.predicted;

  MoodEntry withMinutes(double m) => MoodEntry(at: at, mood: mood, source: source, minutes: m);

  Map<String, dynamic> toJson() => {'at': at.toIso8601String(), 'mood': mood.name, 'source': source.name, 'minutes': minutes};

  static MoodEntry? fromJson(Object? j) {
    if (j is! Map) return null;
    final at = DateTime.tryParse('${j['at']}');
    final mood = Mood.byName(j['mood'] as String?);
    if (at == null || mood == null) return null;
    return MoodEntry(
      at: at,
      mood: mood,
      source: MoodSource.values.where((s) => s.name == j['source']).firstOrNull ?? MoodSource.asked,
      minutes: (j['minutes'] as num?)?.toDouble() ?? 0,
    );
  }

  /// What the mood model may see: when, the mood, minutes read. Nothing else.
  Map<String, dynamic> forModel(DateTime now) => {
        'weekday': at.weekday,
        'hour': at.hour,
        'mood': mood.name,
        'minutes': math.min(600, minutes.roundToDouble()),
        'days_ago': now.difference(at).inDays.clamp(0, 366),
        'source': source.name,
      };
}

/// A predicted mood for one time slot.
class MoodGuess {
  const MoodGuess({required this.slot, required this.mood, this.reason = '', required this.by});

  final String slot;
  final Mood mood;
  final String reason;
  final MoodBy by;

  Map<String, dynamic> toJson() => {'slot': slot, 'mood': mood.name, 'reason': reason, 'by': by.name};

  static MoodGuess? fromJson(Object? j) {
    if (j is! Map) return null;
    final mood = Mood.byName(j['mood'] as String?);
    if (mood == null) return null;
    return MoodGuess(
      slot: '${j['slot']}',
      mood: mood,
      reason: '${j['reason'] ?? ''}',
      by: MoodBy.values.where((b) => b.name == j['by']).firstOrNull ?? MoodBy.habit,
    );
  }
}

class MoodState {
  const MoodState({this.log = const [], this.lastAsked, this.current, this.currentAt, this.currentSource, this.guess});

  final List<MoodEntry> log;
  final DateTime? lastAsked;

  /// The mood in use now, and where it came from.
  final Mood? current;
  final DateTime? currentAt;
  final MoodSource? currentSource;

  /// The prediction for the current time slot (made ahead, used on open).
  final MoodGuess? guess;

  List<MoodEntry> get answers => [for (final e in log) if (e.answered) e];

  MoodState copyWith({
    List<MoodEntry>? log,
    DateTime? lastAsked,
    Mood? current,
    DateTime? currentAt,
    MoodSource? currentSource,
    MoodGuess? guess,
  }) =>
      MoodState(
        log: log ?? this.log,
        lastAsked: lastAsked ?? this.lastAsked,
        current: current ?? this.current,
        currentAt: currentAt ?? this.currentAt,
        currentSource: currentSource ?? this.currentSource,
        guess: guess ?? this.guess,
      );

  Map<String, dynamic> toJson() => {
        'log': [for (final e in log) e.toJson()],
        'lastAsked': lastAsked?.toIso8601String(),
        'current': current?.name,
        'currentAt': currentAt?.toIso8601String(),
        'currentSource': currentSource?.name,
        'guess': guess?.toJson(),
      };

  factory MoodState.fromJson(Map<String, dynamic> j) => MoodState(
        log: [for (final e in (j['log'] as List?) ?? const []) ?MoodEntry.fromJson(e)],
        lastAsked: DateTime.tryParse('${j['lastAsked']}'),
        current: Mood.byName(j['current'] as String?),
        currentAt: DateTime.tryParse('${j['currentAt']}'),
        currentSource: MoodSource.values.where((s) => s.name == j['currentSource']).firstOrNull,
        guess: MoodGuess.fromJson(j['guess']),
      );
}

/// The model's instructions. Keep in step with server/src/mood/suggest.ts.
const moodSystem = 'You suggest a reading mood for Cloro, a reading app. You get a summary of when one reader has read and how they felt. '
    'Reply with JSON only: {"mood": "<calm|cozy|focused|energised|dreamy|reflective|restless>", "reason": "<at most 12 words>"}.';

const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
String _dayType(int weekday) => weekday >= 6 ? 'weekend' : 'weekday';
String _hh(int hour) => hour.toString().padLeft(2, '0');

/// The question for Gemma: answers counted by time of day (corrections count
/// double), then recent sessions. The same text as the server's
/// `buildMoodPrompt`.
String buildMoodPrompt(List<Map<String, dynamic>> log, int weekday, int hour) {
  final recent = [for (final e in log) if ((e['days_ago'] as int) <= 60) e];
  final counts = <String, Map<String, int>>{};
  for (final e in recent) {
    if (e['source'] == 'predicted') continue;
    final key = '${_dayType(e['weekday'] as int)} ${slotOf(e['hour'] as int)}';
    final m = counts.putIfAbsent(key, () => {});
    m[e['mood'] as String] = (m[e['mood']] ?? 0) + (e['source'] == 'corrected' ? 2 : 1);
  }
  final lines = <String>[];
  for (final d in ['weekday', 'weekend']) {
    for (final s in ['morning', 'afternoon', 'evening', 'night']) {
      final m = counts['$d $s'];
      if (m == null) continue;
      final parts = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      lines.add('- $d $s: ${parts.map((p) => '${p.key} ${p.value}').join(', ')}');
    }
  }
  final sessions = ([...recent]..sort((a, b) => (a['days_ago'] as int).compareTo(b['days_ago'] as int)))
      .take(12)
      .map((e) => '- ${_days[(e['weekday'] as int) - 1]} ${_hh(e['hour'] as int)}:00 ${e['mood']}, ${(e['minutes'] as num).round()} min');
  return [
    'Now: ${_days[weekday - 1]} ${_hh(hour)}:00 (${_dayType(weekday)} ${slotOf(hour)}).',
    'How they usually feel (answers in the last 60 days; corrections count double):',
    ...(lines.isEmpty ? ['- no answers yet'] : lines),
    'Recent sessions (newest first):',
    ...(sessions.isEmpty ? ['- none'] : sessions),
    'Which mood suits them right now?',
  ].join('\n');
}

/// The mood and reason from a model reply, or null when it isn't one of the moods.
({Mood mood, String reason})? parseMoodReply(String reply) {
  final json = RegExp(r'\{[\s\S]*?\}').firstMatch(reply)?.group(0);
  if (json != null) {
    try {
      final o = jsonDecode(json);
      final mood = o is Map ? Mood.byName('${o['mood']}') : null;
      if (mood == null) return null;
      final reason = '${o['reason'] ?? ''}'.replaceAll(RegExp(r'\s+'), ' ').trim();
      return (mood: mood, reason: reason.length > 120 ? reason.substring(0, 120) : reason);
    } catch (_) {
      return null;
    }
  }
  // A bare word ("cozy") is fine too.
  final mood = Mood.byName(reply.replaceAll(RegExp('[^a-zA-Z]'), ''));
  return mood == null ? null : (mood: mood, reason: '');
}

/// Without a model: the mood you most often had at this time of day (and on
/// this kind of day), weighted by how long you read; corrections count double.
Mood fallbackMood(List<MoodEntry> log, DateTime now) {
  final answers = [for (final e in log) if (e.answered && now.difference(e.at).inDays <= 60) e];
  Mood? best(Iterable<MoodEntry> es) {
    final score = <Mood, double>{};
    final last = <Mood, DateTime>{};
    for (final e in es) {
      score[e.mood] = (score[e.mood] ?? 0) + (1 + e.minutes / 30) * (e.source == MoodSource.corrected ? 2 : 1);
      if (last[e.mood] == null || e.at.isAfter(last[e.mood]!)) last[e.mood] = e.at;
    }
    if (score.isEmpty) return null;
    return score.keys.reduce((a, b) => score[a]! > score[b]! || (score[a] == score[b] && last[a]!.isAfter(last[b]!)) ? a : b);
  }

  final slot = slotOf(now.hour);
  final weekend = now.weekday >= 6;
  return best(answers.where((e) => slotOf(e.at.hour) == slot && (e.at.weekday >= 6) == weekend)) ??
      best(answers.where((e) => slotOf(e.at.hour) == slot)) ??
      best(answers) ??
      Mood.calm;
}

class MoodController extends Notifier<MoodState> {
  /// Injectable clock for tests.
  DateTime Function() clock = DateTime.now;

  /// While learning: ask at most this often.
  static const askEvery = Duration(hours: 3);

  /// After learning: a check-in this often.
  static const checkInEvery = Duration(days: 7);

  /// How long each way of predicting may take.
  static const timeout = Duration(seconds: 6);

  /// The on-device model that can predict moods.
  static const gemmaModelId = 'gemma-4-e2b';

  static const _maxLog = 400;

  @override
  MoodState build() {
    final json = ref.read(storeProvider).doc('mood');
    return json == null ? const MoodState() : MoodState.fromJson(json);
  }

  void _set(MoodState next) {
    state = next;
    ref.read(storeProvider).saveDoc('mood', next.toJson());
  }

  /// Whether moods pick the scene (not when the story does, on paid plans).
  bool get active {
    final s = ref.read(settingsProvider);
    return s.moodScenes && !(s.autoScene && s.tier.paid);
  }

  /// The mood set in the last 6 hours, if any (it goes on the session's card).
  Mood? get recent {
    final at = state.currentAt;
    return at != null && clock().difference(at) <= const Duration(hours: 6) ? state.current : null;
  }

  /// Still learning: under 15 answers, unless two weeks have passed with at
  /// least 5.
  bool get learning {
    final answers = state.answers;
    if (answers.length >= 15) return false;
    return !(answers.length >= 5 && clock().difference(answers.first.at).inDays >= 14);
  }

  /// Whether to ask now: every 3 hours at most while learning, then a weekly
  /// check-in.
  bool shouldAsk() {
    if (!active || ref.read(settingsProvider).moodAsk == MoodAsk.never) return false;
    final last = state.lastAsked;
    if (last == null) return true;
    return clock().difference(last) >= (learning ? askEvery : checkInEvery);
  }

  /// You said how you feel (or [corrected] a guess): it's learnt and the
  /// book opens in that mood's scene.
  void answer(Mood mood, {bool corrected = false}) {
    final now = clock();
    final source = corrected ? MoodSource.corrected : MoodSource.asked;
    _set(state.copyWith(
      log: _capped([...state.log, MoodEntry(at: now, mood: mood, source: source)]),
      lastAsked: now,
      current: mood,
      currentAt: now,
      currentSource: source,
    ));
    _apply(mood, now);
  }

  /// "Not now": not asked again for a while.
  void skip() => _set(state.copyWith(lastAsked: clock()));

  /// Credits reading time to the session's mood (if it was set in the last 6 hours).
  void addMinutes(int dwellMs) {
    if (state.log.isEmpty || dwellMs <= 0) return;
    final last = state.log.last;
    if (clock().difference(last.at) > const Duration(hours: 6)) return;
    _set(state.copyWith(log: [...state.log.sublist(0, state.log.length - 1), last.withMinutes(last.minutes + dwellMs / 60000)]));
  }

  /// Uses the prediction for now, once per time slot. Returns the mood when
  /// it was applied (for the "· change" chip).
  Mood? applyPrediction() {
    if (!active || learning) return null;
    final now = clock();
    final key = slotKey(now);
    final at = state.currentAt;
    if (at != null && slotKey(at) == key) return null; // already set for this part of the day
    final guess = state.guess;
    if (guess == null || guess.slot != key) return null;
    _set(state.copyWith(
      log: _capped([...state.log, MoodEntry(at: now, mood: guess.mood, source: MoodSource.predicted)]),
      current: guess.mood,
      currentAt: now,
      currentSource: MoodSource.predicted,
    ));
    _apply(guess.mood, now);
    return guess.mood;
  }

  /// Predicts the mood for this part of the day, unless already done.
  Future<void> refreshPrediction() async {
    if (!active || learning) return;
    final now = clock();
    final key = slotKey(now);
    if (state.guess?.slot == key) return;
    final guess = await predict(now);
    _set(state.copyWith(guess: guess));
  }

  /// Gemma on the phone, else Gemma on the server, else your own habit.
  Future<MoodGuess> predict(DateTime now) async {
    final key = slotKey(now);
    final log = [
      for (final e in state.log.reversed)
        if (now.difference(e.at).inDays <= 60) e.forModel(now),
    ].take(200).toList();

    final ai = ref.read(onDeviceAiProvider.notifier);
    if (ai.usable && ref.read(onDeviceAiProvider).model?.id == gemmaModelId) {
      final prompt = buildMoodPrompt(log, now.weekday, now.hour);
      final reply = await ai
          .run((llm) => llm.generate(prompt, system: moodSystem, maxOutputTokens: 60, temperature: 0.2), urgent: true)
          .timeout(timeout, onTimeout: () => null)
          .catchError((_) => null);
      final parsed = reply == null ? null : parseMoodReply(reply);
      if (parsed != null) return MoodGuess(slot: key, mood: parsed.mood, reason: parsed.reason, by: MoodBy.phone);
    }

    final api = ref.read(apiProvider);
    if (api.enabled) {
      try {
        final r = await api
            .moodSuggest(log: log, weekday: now.weekday, hour: now.hour, tier: ref.read(settingsProvider).tier.name)
            .timeout(timeout);
        final mood = Mood.byName(r?.mood);
        if (mood != null) return MoodGuess(slot: key, mood: mood, reason: r!.reason, by: MoodBy.server);
      } catch (_) {/* fall back to the habit */}
    }

    return MoodGuess(slot: key, mood: fallbackMood(state.log, now), by: MoodBy.habit);
  }

  void _apply(Mood mood, DateTime now) {
    if (!active) return;
    final settings = ref.read(settingsProvider);
    final scene = mood.sceneAt(now, settings.appearance);
    if (settings.vibe != scene) ref.read(settingsProvider.notifier).update((s) => s.copyWith(vibe: scene));
  }

  static List<MoodEntry> _capped(List<MoodEntry> log) => log.length > _maxLog ? log.sublist(log.length - _maxLog) : log;
}

final moodProvider = NotifierProvider<MoodController, MoodState>(MoodController.new);
