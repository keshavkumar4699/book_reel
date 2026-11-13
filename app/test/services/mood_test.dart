import 'dart:io';

import 'package:book_reel/data/api_client.dart';
import 'package:book_reel/data/json_store.dart';
import 'package:book_reel/data/settings.dart';
import 'package:book_reel/data/settings_provider.dart';
import 'package:book_reel/data/store_provider.dart';
import 'package:book_reel/services/mood.dart';
import 'package:book_reel/services/on_device_ai.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'on_device_ai_test.dart' show FakeProbe, FakeRuntime, ScriptedLlm, gb;

/// The server's Gemma, faked.
class FakeMoodApi extends BookReelApi {
  FakeMoodApi(this.reply, {bool online = true}) : super(baseUrl: online ? 'http://mood.test' : '', deviceId: 'device-0123456789');
  final ({String mood, String reason})? reply;
  final logs = <List<Map<String, dynamic>>>[];

  @override
  Future<({String mood, String reason})?> moodSuggest({
    required List<Map<String, dynamic>> log,
    required int weekday,
    required int hour,
    required String tier,
  }) async {
    logs.add(log);
    return reply;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime now;

  Future<ProviderContainer> container({BookReelApi? api}) async {
    final dir = Directory.systemTemp.createTempSync('mood');
    final store = await JsonStore.open(dir);
    final c = ProviderContainer(overrides: [
      storeProvider.overrideWithValue(store),
      apiProvider.overrideWithValue(api ?? FakeMoodApi(null, online: false)),
    ]);
    addTearDown(() async {
      c.dispose();
      await store.flush();
      dir.deleteSync(recursive: true);
    });
    c.read(moodProvider.notifier).clock = () => now;
    return c;
  }

  /// [n] answers of [mood] at [hour], one a day, ending yesterday.
  void answerDays(ProviderContainer c, int n, Mood mood, {int hour = 21, DateTime? until}) {
    final end = until ?? now;
    for (var i = n; i >= 1; i--) {
      final at = DateTime(end.year, end.month, end.day - i, hour);
      final saved = now;
      now = at;
      c.read(moodProvider.notifier).answer(mood);
      now = saved;
    }
  }

  group('asking', () {
    test('while learning: at most every 3 hours; "Not now" counts as asked', () async {
      now = DateTime(2026, 11, 10, 20); // Tuesday evening
      final c = await container();
      final mood = c.read(moodProvider.notifier);
      expect(mood.learning, isTrue);
      expect(mood.shouldAsk(), isTrue, reason: 'never asked');
      mood.skip();
      now = now.add(const Duration(hours: 2, minutes: 59));
      expect(mood.shouldAsk(), isFalse);
      now = now.add(const Duration(minutes: 1));
      expect(mood.shouldAsk(), isTrue);
      mood.answer(Mood.cozy);
      expect(mood.shouldAsk(), isFalse);
      expect(c.read(moodProvider).current, Mood.cozy);
    });

    test('learning ends at 15 answers, or after two weeks with 5; then a weekly check-in', () async {
      now = DateTime(2026, 11, 20, 21);
      final c = await container();
      final mood = c.read(moodProvider.notifier);
      answerDays(c, 13, Mood.cozy);
      final evening = now;
      now = DateTime(2026, 11, 20, 8);
      mood.answer(Mood.calm);
      expect(c.read(moodProvider).answers, hasLength(14));
      expect(mood.learning, isTrue, reason: '14 answers in under two weeks: still learning');
      now = DateTime(2026, 11, 20, 9);
      mood.answer(Mood.calm);
      expect(c.read(moodProvider).answers, hasLength(15));
      expect(mood.learning, isFalse);
      now = evening;
      // Last asked this morning: no check-in until a week has passed.
      expect(mood.shouldAsk(), isFalse);
      now = now.add(const Duration(days: 7));
      expect(mood.shouldAsk(), isTrue);

      // Few answers, but two weeks of them.
      now = DateTime(2026, 11, 20, 21);
      final d = await container();
      answerDays(d, 5, Mood.calm, until: DateTime(2026, 11, 8));
      expect(d.read(moodProvider.notifier).learning, isFalse);
    });

    test('"Never", mood scenes off, or the story picking: no asking', () async {
      now = DateTime(2026, 11, 10, 20);
      final c = await container();
      final mood = c.read(moodProvider.notifier);
      final settings = c.read(settingsProvider.notifier);
      settings.update((s) => s.copyWith(moodAsk: MoodAsk.never));
      expect(mood.shouldAsk(), isFalse);
      settings.update((s) => s.copyWith(moodAsk: MoodAsk.learning, moodScenes: false));
      expect(mood.shouldAsk(), isFalse);
      settings.update((s) => s.copyWith(moodScenes: true, tier: Tier.plus, autoScene: true));
      expect(mood.shouldAsk(), isFalse, reason: '"Let the story decide" picks the scene');
      settings.update((s) => s.copyWith(autoScene: false));
      expect(mood.shouldAsk(), isTrue);
    });
  });

  group('scenes', () {
    test('a mood opens its scene: by day, by night, or as Appearance says', () async {
      expect(Mood.cozy.sceneAt(DateTime(2026, 11, 10, 21), AppAppearance.system), Vibe.cafe);
      expect(Mood.cozy.sceneAt(DateTime(2026, 11, 10, 10), AppAppearance.system), Vibe.snow);
      expect(Mood.energised.sceneAt(DateTime(2026, 11, 10, 10), AppAppearance.system), Vibe.ocean);
      expect(Mood.energised.sceneAt(DateTime(2026, 11, 10, 10), AppAppearance.dark), Vibe.city);
      expect(Mood.calm.sceneAt(DateTime(2026, 11, 10, 23), AppAppearance.light), Vibe.meadow);
      expect(Mood.focused.sceneAt(DateTime(2026, 11, 10, 23), AppAppearance.system), Vibe.paper);

      now = DateTime(2026, 11, 10, 21);
      final c = await container();
      c.read(moodProvider.notifier).answer(Mood.reflective);
      expect(c.read(settingsProvider).vibe, Vibe.rain);
      c.read(settingsProvider.notifier).update((s) => s.copyWith(moodScenes: false));
      c.read(moodProvider.notifier).answer(Mood.calm);
      expect(c.read(settingsProvider).vibe, Vibe.rain, reason: 'mood scenes are off');
    });

    test('reading time is credited to the session’s mood', () async {
      now = DateTime(2026, 11, 10, 21);
      final c = await container();
      final mood = c.read(moodProvider.notifier);
      mood.answer(Mood.cozy);
      mood.addMinutes(90 * 1000);
      mood.addMinutes(30 * 1000);
      expect(c.read(moodProvider).log.last.minutes, closeTo(2, 0.001));
      now = now.add(const Duration(hours: 7));
      mood.addMinutes(60 * 1000);
      expect(c.read(moodProvider).log.last.minutes, closeTo(2, 0.001), reason: 'a later session without a mood');
    });
  });

  group('predicting', () {
    test('the habit: the usual mood for this time of day and kind of day', () {
      final t = DateTime(2026, 11, 10, 21); // Tuesday 21:00
      MoodEntry e(int daysAgo, int hour, Mood m, {MoodSource s = MoodSource.asked, double minutes = 0}) =>
          MoodEntry(at: DateTime(t.year, t.month, t.day - daysAgo, hour), mood: m, source: s, minutes: minutes);
      final log = [
        e(1, 21, Mood.cozy), // Monday evening
        e(2, 20, Mood.cozy), // Sunday evening (weekend)
        e(3, 21, Mood.dreamy), // Saturday evening (weekend)
        e(6, 21, Mood.calm, minutes: 60), // Wednesday evening, long read
        e(7, 9, Mood.focused), // morning
      ];
      expect(fallbackMood(log, t), Mood.calm, reason: 'weekday evenings: calm (1 + 60/30 = 3) beats cozy (1)');
      expect(fallbackMood([...log, e(0, 18, Mood.cozy, s: MoodSource.corrected)], t), Mood.cozy,
          reason: 'a correction counts double');
      expect(fallbackMood(log, DateTime(2026, 11, 14, 19)), Mood.cozy, reason: 'weekend evenings: a tie, the latest wins');
      expect(fallbackMood(log, DateTime(2026, 11, 11, 8)), Mood.focused);
      expect(fallbackMood(log, DateTime(2026, 11, 11, 14)), Mood.calm, reason: 'no afternoons yet: the overall favourite');
      expect(fallbackMood(const [], t), Mood.calm);
      expect(fallbackMood([e(70, 21, Mood.restless)], t), Mood.calm, reason: 'older than 60 days');
      expect(fallbackMood([e(1, 21, Mood.restless, s: MoodSource.predicted)], t), Mood.calm, reason: 'only your own answers');
    });

    test('Gemma’s reply must be one of the moods', () {
      expect(parseMoodReply('Sure! {"mood": "Cozy", "reason": "Evenings are cozy for you."}'),
          (mood: Mood.cozy, reason: 'Evenings are cozy for you.'));
      expect(parseMoodReply('{"mood":"energized"}')?.mood, Mood.energised);
      expect(parseMoodReply('calm'), (mood: Mood.calm, reason: ''));
      expect(parseMoodReply('{"mood": "happy"}'), isNull);
      expect(parseMoodReply('I think something calm and cozy.'), isNull);
      expect(parseMoodReply('{oops}'), isNull);
    });

    test('the prompt: counts by time of day and recent sessions, nothing else', () {
      final t = DateTime(2026, 11, 11, 21); // Wednesday
      final log = [
        MoodEntry(at: DateTime(2026, 11, 10, 21), mood: Mood.cozy, source: MoodSource.asked, minutes: 34).forModel(t),
        MoodEntry(at: DateTime(2026, 11, 9, 8), mood: Mood.focused, source: MoodSource.corrected).forModel(t),
        MoodEntry(at: DateTime(2026, 11, 9, 21), mood: Mood.dreamy, source: MoodSource.predicted).forModel(t),
      ];
      expect(log.first.keys.toSet(), {'weekday', 'hour', 'mood', 'minutes', 'days_ago', 'source'});
      final prompt = buildMoodPrompt(log, t.weekday, t.hour);
      expect(prompt, startsWith('Now: Wed 21:00 (weekday evening).'));
      expect(prompt, contains('- weekday evening: cozy 1\n'));
      expect(prompt, contains('- weekday morning: focused 2'));
      expect(prompt, isNot(contains('evening: dreamy')), reason: 'predictions are not answers');
      expect(prompt, contains('- Tue 21:00 cozy, 34 min'));
    });

    Future<ProviderContainer> learnt({BookReelApi? api}) async {
      now = DateTime(2026, 11, 20, 21);
      final c = await container(api: api);
      answerDays(c, 15, Mood.cozy);
      expect(c.read(moodProvider.notifier).learning, isFalse);
      return c;
    }

    test('Gemma on the phone first (Free plan, Gemma downloaded)', () async {
      final runtime = FakeRuntime()..installed.add('gemma-4-e2b');
      var reply = '{"mood": "dreamy", "reason": "Late reads drift."}';
      runtime.llm = ScriptedLlm((_) => reply);
      OnDeviceAiController.runtimeFactory = () => runtime;
      OnDeviceAiController.probeFactory = () => FakeProbe(const DeviceProfile(supported: true, totalRamBytes: 8 * gb));
      addTearDown(() {
        OnDeviceAiController.runtimeFactory = () => null;
        OnDeviceAiController.probeFactory = PlatformDeviceProbe.new;
      });
      final api = FakeMoodApi((mood: 'calm', reason: 'server'));
      final c = await learnt(api: api);
      c.read(settingsProvider.notifier).update((s) => s.copyWith(localModel: 'gemma-4-e2b'));
      c.read(onDeviceAiProvider);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(c.read(onDeviceAiProvider.notifier).usable, isTrue);

      final guess = await c.read(moodProvider.notifier).predict(now);
      expect((guess.mood, guess.by, guess.reason), (Mood.dreamy, MoodBy.phone, 'Late reads drift.'));
      expect(runtime.llm.prompts.single, contains('weekday evening: cozy'));
      expect(api.logs, isEmpty, reason: 'the server is not asked');

      // A reply that isn't a mood: the server's Gemma is asked instead.
      reply = 'I cannot tell.';
      final next = await c.read(moodProvider.notifier).predict(now);
      expect((next.mood, next.by), (Mood.calm, MoodBy.server));
    });

    test('Gemma on the server, then the habit when it has no answer', () async {
      final api = FakeMoodApi((mood: 'energised', reason: 'Fresh start.'));
      final c = await learnt(api: api);
      final guess = await c.read(moodProvider.notifier).predict(now);
      expect((guess.mood, guess.by, guess.reason), (Mood.energised, MoodBy.server, 'Fresh start.'));
      final sent = api.logs.single;
      expect(sent, hasLength(15));
      expect(sent.first.keys.toSet(), {'weekday', 'hour', 'mood', 'minutes', 'days_ago', 'source'}, reason: 'the mood log only');

      final offline = await learnt(api: FakeMoodApi((mood: 'grumpy', reason: '')));
      final habit = await offline.read(moodProvider.notifier).predict(now);
      expect((habit.mood, habit.by), (Mood.cozy, MoodBy.habit));
    });

    test('a prediction is made once per part of the day and applied once, then can be corrected', () async {
      final api = FakeMoodApi((mood: 'reflective', reason: 'Rainy evenings.'));
      final c = await learnt(api: api);
      final mood = c.read(moodProvider.notifier);
      expect(mood.applyPrediction(), isNull, reason: 'nothing predicted yet');
      await mood.refreshPrediction();
      await mood.refreshPrediction();
      expect(api.logs, hasLength(1), reason: 'cached for this evening');
      expect(mood.applyPrediction(), Mood.reflective);
      expect(c.read(settingsProvider).vibe, Vibe.rain);
      expect(c.read(moodProvider).currentSource, MoodSource.predicted);
      expect(mood.applyPrediction(), isNull, reason: 'once per part of the day');

      mood.answer(Mood.calm, corrected: true);
      expect(c.read(moodProvider).log.last.source, MoodSource.corrected);
      expect(c.read(settingsProvider).vibe, Vibe.night);

      // Tomorrow morning: a new prediction.
      now = DateTime(2026, 11, 21, 9);
      await mood.refreshPrediction();
      expect(api.logs, hasLength(2));
      expect(mood.applyPrediction(), Mood.reflective);
      expect(c.read(settingsProvider).vibe, Vibe.forest, reason: 'reflective by day');
    });

    test('the log survives a restart', () async {
      now = DateTime(2026, 11, 10, 21);
      final c = await container();
      c.read(moodProvider.notifier).answer(Mood.dreamy);
      final again = MoodState.fromJson(c.read(moodProvider).toJson());
      expect(again.log.single.mood, Mood.dreamy);
      expect(again.current, Mood.dreamy);
      expect(again.lastAsked, now);
    });
  });
}
