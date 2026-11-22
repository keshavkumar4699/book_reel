import 'dart:io';

import 'package:book_reel/core/habit/habit_engine.dart';
import 'package:book_reel/data/api_client.dart';
import 'package:book_reel/data/habit.dart';
import 'package:book_reel/data/json_store.dart';
import 'package:book_reel/data/notebook.dart';
import 'package:book_reel/data/settings.dart';
import 'package:book_reel/data/settings_provider.dart';
import 'package:book_reel/data/store_provider.dart';
import 'package:book_reel/features/profile/profile_screen.dart';
import 'package:book_reel/ui/kit.dart';
import 'package:book_reel/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../data/fake_server.dart';

void main() {
  late Directory dir;
  late ProviderContainer c;
  late FakeServer server;
  late JsonStore store;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('profile');
    server = FakeServer()..takenHandles.add('taken.name');
    store = await JsonStore.open(dir);
    c = ProviderContainer(overrides: [
      storeProvider.overrideWithValue(store),
      apiProvider.overrideWithValue(BookReelApi(baseUrl: 'http://fake', deviceId: 'dev1', httpClient: server.client)),
    ]);
  });

  tearDown(() {
    c.dispose();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<void> open(WidgetTester tester, {ProviderContainer? container}) async {
    tester.view.physicalSize = const Size(1236, 2745);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container ?? c,
      child: MaterialApp(theme: buildAppTheme(Kit.forScene(Vibe.night, ReadingTheme.of(ReadingThemeId.paper))), home: const ProfileScreen()),
    ));
    await tester.pumpAndSettle();
  }

  /// Today: 30 minutes, 12 cards, 1,450 words (3 reels skimmed). A day last
  /// year: 100 minutes, 40 cards, 9,800 words.
  void readingHistory() {
    final now = DateTime.now();
    store.saveDoc(
      'habit',
      HabitState(
        stats: {
          dateKey(now): const DailyStat(verifiedCards: 12, skimmedCards: 3, minutes: 30, words: 1450),
          dateKey(DateTime(now.year - 1, 6, 3)): const DailyStat(verifiedCards: 40, minutes: 100, words: 9800),
        },
        streak: StreakState(current: 5, best: 9, lastGoalDate: dateKey(now)),
      ).toJson(),
    );
  }

  Finder figure(String value, String label) => find.bySemanticsLabel('$value $label');

  /// The haptics played from now on (their Flutter type names).
  List<String> recordHaptics(WidgetTester tester) {
    final played = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') played.add('${call.arguments}');
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    return played;
  }

  testWidgets('header: who you are, followers and following, up to 3 genres', (tester) async {
    c.read(settingsProvider.notifier).update((s) => s.copyWith(
        displayName: 'Asha',
        username: 'asha.reads',
        pronouns: 'she/her',
        bio: 'Classics on the commute.',
        interests: ['Fantasy', 'History', 'Poetry', 'Science']));
    await open(tester);
    expect(find.text('@asha.reads'), findsOneWidget, reason: 'in the top bar');
    expect(find.textContaining('she/her', findRichText: true), findsOneWidget);
    expect(find.text('1 follower'), findsOneWidget, reason: 'Ravi follows you (from the server)');
    expect(find.text('0 following'), findsOneWidget);
    expect(find.text('Classics on the commute.'), findsOneWidget);
    expect(find.text('Fantasy · History · Poetry'), findsOneWidget, reason: 'never more than 3');
    expect(find.text('Edit profile'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
  });

  testWidgets('offline: no follower counts rather than false zeros', (tester) async {
    final offline = ProviderContainer(overrides: [
      storeProvider.overrideWithValue(store),
      apiProvider.overrideWithValue(BookReelApi(baseUrl: '', deviceId: 'dev1')),
    ]);
    addTearDown(offline.dispose);
    await open(tester, container: offline);
    expect(find.textContaining('follower'), findsNothing);
    expect(find.textContaining('following'), findsNothing);
  });

  testWidgets('this week, streak, stats, trophies, books and quotes', (tester) async {
    readingHistory();
    c.read(notebookProvider.notifier).addHighlight(bookId: 'b', bookTitle: 'Walden', sid: 'c0.b0.s0', text: 'Simplify, simplify.');
    await open(tester);
    // The page builds as it scrolls: bring each section into view first.
    Future<void> scrollTo(Finder f) => tester.scrollUntilVisible(f, 300, scrollable: find.byType(Scrollable).first);
    final kit = Kit.of(tester.element(find.byType(ProfileScreen)));
    Color? colour(String value, String label) =>
        tester.widget<Text>(find.descendant(of: figure(value, label).first, matching: find.text(value))).style?.color;
    // This week: today's reading only; minutes, the headline, in blue.
    expect(figure('30', 'minutes'), findsOneWidget);
    expect(colour('30', 'minutes'), kit.activity);
    expect(figure('12', 'cards'), findsNWidgets(2), reason: 'this week, and this month in Stats');
    expect(colour('12', 'cards'), isNot(kit.activity), reason: 'one figure in colour, not all');
    // A circle round each day: today's, the week's best, is the largest; days without reading are empty rings.
    final today = DateTime.now().weekday - 1;
    expect(find.byType(DayCircle), findsNWidgets(7));
    expect(find.bySemanticsLabel(RegExp(r', today: 30 minutes, 12 cards$')), findsOneWidget);
    double width(int i) => tester.getSize(find.descendant(of: find.byType(DayCircle).at(i), matching: find.byType(AnimatedContainer))).width;
    expect(width(today), DayCircle.largest);
    expect(width((today + 1) % 7), DayCircle.smallest);
    expect(find.textContaining('Today  ·  30 min', findRichText: true), findsOneWidget);
    // Tap another day: its figures, with a tap you can feel.
    final haptics = recordHaptics(tester);
    final other = (today + 1) % 7;
    const names = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    await tester.tap(find.byType(DayCircle).at(other));
    await tester.pumpAndSettle();
    expect(find.textContaining('${names[other]}  ·  0 min', findRichText: true), findsOneWidget);
    expect(haptics, ['HapticFeedbackType.lightImpact']);
    // Streak: the current streak in green, and the calendar in GitHub's greens.
    await scrollTo(find.text('Last 12 weeks'));
    expect(figure('5', 'day streak'), findsOneWidget);
    expect(colour('5', 'day streak'), kit.growth);
    expect(figure('9', 'best'), findsOneWidget);
    expect(find.text('Last 12 weeks'), findsOneWidget);
    expect(find.bySemanticsLabel('Reading calendar for the last 12 weeks: 1 day with reading, the goal met on 0'), findsOneWidget);
    final cells = tester.widgetList<Container>(find.descendant(of: find.byType(StreakCalendar), matching: find.byType(Container)));
    final greens = cells.map((c) => (c.decoration as BoxDecoration?)?.color).toList();
    // Today: 12 of 20 cards, over a third of the goal (the deepest green is a goal met).
    expect(greens.where((g) => g == kit.streakScale[2]), hasLength(1));
    expect(greens.where((g) => g == kit.streakScale[0]), hasLength(greens.where((g) => g != null).length - 1));
    // Stats: this month, this year, then all time.
    await scrollTo(find.text('All time'));
    expect(find.text('This month'), findsOneWidget);
    expect(figure('30 min', 'reading time'), findsOneWidget);
    expect(colour('30 min', 'reading time'), kit.activity);
    expect(figure('1', 'reading day'), findsOneWidget);
    expect(colour('1', 'reading day'), kit.growth);
    await tester.tap(find.text('This year'));
    await tester.pumpAndSettle();
    expect(figure('30 min', 'reading time'), findsOneWidget, reason: 'the day last year is not in it');
    await tester.ensureVisible(find.text('All time'));
    await tester.tap(find.text('All time'));
    await tester.pumpAndSettle();
    expect(figure('2 h 10 min', 'reading time'), findsOneWidget);
    expect(figure('52', 'cards'), findsOneWidget);
    expect(figure('11k', 'words read'), findsOneWidget, reason: '1,450 + 9,800');
    expect(figure('3', 'reels skimmed (not counted)'), findsOneWidget);
    expect(figure('2', 'reading days'), findsOneWidget);
    // Trophies earned, and the next of each kind.
    await scrollTo(find.text('Trophies'));
    await scrollTo(find.bySemanticsLabel('Trophy: Best week: 100 min'));
    expect(find.bySemanticsLabel('Trophy: 7-day streak'), findsOneWidget);
    expect(find.bySemanticsLabel('Next trophy: 14-day streak'), findsOneWidget);
    expect(find.bySemanticsLabel('Next trophy: First book'), findsOneWidget);
    expect(find.bySemanticsLabel('Next trophy: 100 cards'), findsOneWidget);
    expect(find.bySemanticsLabel('Trophy: Best week: 100 min'), findsOneWidget);
    // No books yet; one quote.
    await scrollTo(find.text('No books yet'));
    await scrollTo(find.text('Simplify, simplify.'));
    expect(find.text('Saved quotes'), findsOneWidget);
  });

  test('day circles grow by area; streak levels follow the goal', () {
    expect(DayCircle.diameterFor(0, 30), DayCircle.smallest);
    expect(DayCircle.diameterFor(30, 30), DayCircle.largest);
    // Half the best day's minutes: half the extra area.
    const s = DayCircle.smallest, l = DayCircle.largest;
    final half = DayCircle.diameterFor(15, 30);
    expect(half * half, closeTo(s * s + (l * l - s * s) / 2, 1e-6));
    const goal = GoalConfig(unit: GoalUnit.cards, dailyTarget: 9, mode: GoalMode.daily, weeklyDays: 5);
    expect(streakLevel(null, goal), 0);
    expect(streakLevel(const DailyStat(minutes: 2), goal), 1, reason: 'read, though no cards yet');
    expect(streakLevel(const DailyStat(verifiedCards: 2), goal), 1);
    expect(streakLevel(const DailyStat(verifiedCards: 4), goal), 2);
    expect(streakLevel(const DailyStat(verifiedCards: 7), goal), 3);
    expect(streakLevel(const DailyStat(verifiedCards: 9), goal), 4);
    expect(StatsPeriod.month.covers('2026-11-03', DateTime(2026, 11, 22)), isTrue);
    expect(StatsPeriod.month.covers('2026-10-31', DateTime(2026, 11, 22)), isFalse);
    expect(StatsPeriod.year.covers('2026-01-01', DateTime(2026, 11, 22)), isTrue);
    expect(StatsPeriod.year.covers('2025-12-31', DateTime(2026, 11, 22)), isFalse);
  });

  testWidgets('pronouns: he/him, she/her, they/them, or your own', (tester) async {
    await open(tester);
    Future<void> save() async {
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text('Edit profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('they/them'));
    await tester.pump();
    await save();
    expect(c.read(settingsProvider).pronouns, 'they/them');

    await tester.tap(find.text('Edit profile'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(3), reason: 'no pronoun field until Custom');
    await tester.tap(find.text('Custom'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(2), 'xe/xem');
    await save();
    expect(c.read(settingsProvider).pronouns, 'xe/xem');
    expect(find.textContaining('xe/xem', findRichText: true), findsOneWidget);

    // Your own pronouns stay "Custom" next time.
    await tester.tap(find.text('Edit profile'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(4));
  });

  testWidgets('genres: up to 3; older saves keep their first 3', (tester) async {
    expect(AppSettings.fromJson({'interests': ['A', 'B', 'C', 'D', 'E']}).interests, ['A', 'B', 'C']);
    await open(tester);
    await tester.tap(find.text('Edit profile'));
    await tester.pumpAndSettle();
    expect(find.text('Pick up to 3 (3 left)'), findsOneWidget);
    for (final g in ['Fantasy', 'History', 'Poetry', 'Science']) {
      await tester.ensureVisible(find.text(g));
      await tester.tap(find.text(g));
      await tester.pump();
    }
    expect(find.text('Pick up to 3 (that’s 3)'), findsOneWidget);
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).interests, ['Fantasy', 'History', 'Poetry'], reason: 'the 4th could not be picked');
  });

  testWidgets('edit profile: a taken or malformed username is refused; the rest is saved', (tester) async {
    await open(tester);
    await tester.tap(find.text('Edit profile'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Asha');
    await tester.enterText(fields.at(1), 'Not Valid!');
    await tester.enterText(fields.at(2), 'Reading my way through the classics.');
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Usernames are 3–24'), findsOneWidget);

    await tester.enterText(fields.at(1), 'taken.name');
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.text('@taken.name is taken. Try another.'), findsOneWidget);
    expect(c.read(settingsProvider).username, '');

    // A reserved name: the server's reason is shown.
    await tester.enterText(fields.at(1), 'support');
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.text('That username is reserved. Try another.'), findsOneWidget);

    // No links in a bio (spam), checked before anything is sent.
    await tester.enterText(fields.at(2), 'Find me at mysite.com');
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Links aren’t allowed in your name or bio.'), findsOneWidget);
    await tester.enterText(fields.at(2), 'Reading my way through the classics.');

    await tester.enterText(fields.at(1), '@Asha.Reads');
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    final s = c.read(settingsProvider);
    expect((s.displayName, s.username, s.bio), ('Asha', 'asha.reads', 'Reading my way through the classics.'));
    expect(server.profiles['dev1'], containsPair('handle', 'asha.reads'));
    expect(find.text('Edit profile'), findsOneWidget, reason: 'back on the profile');
    expect(find.text('Reading my way through the classics.'), findsOneWidget);
  });
}
