import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:book_reel/core/habit/habit_engine.dart';
import 'package:book_reel/data/api_client.dart';
import 'package:book_reel/data/habit.dart';
import 'package:book_reel/data/json_store.dart';
import 'package:book_reel/data/notebook.dart';
import 'package:book_reel/data/settings.dart';
import 'package:book_reel/data/settings_provider.dart';
import 'package:book_reel/data/store_provider.dart';
import 'package:book_reel/features/profile/profile_screen.dart';
import 'package:book_reel/l10n/l10n.dart';
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
    c.read(notebookProvider.notifier).like('b', 'c0.b3.s0',
        quote: LikedQuote(
            bookId: 'b', sid: 'c0.b3.s0', bookTitle: 'Walden', author: 'Thoreau', chapterTitle: 'Economy', text: 'Our life is frittered away by detail.', likedAt: DateTime(2026, 11, 2)));
    await open(tester);
    // The page builds as it scrolls: bring each section into view first.
    Future<void> scrollTo(Finder f) => tester.scrollUntilVisible(f, 300, scrollable: find.byType(Scrollable).first);
    final kit = Kit.of(tester.element(find.byType(ProfileScreen)));
    Color? colour(String value, String label) =>
        tester.widget<Text>(find.descendant(of: figure(value, label).first, matching: find.text(value))).style?.color;
    // The last 7 days, up to today: today's reading only; minutes, the headline, in blue.
    expect(find.text('Last 7 days'), findsOneWidget);
    expect(figure('30', 'minutes'), findsOneWidget);
    expect(colour('30', 'minutes'), kit.activity);
    expect(figure('12', 'cards'), findsNWidgets(2), reason: 'this week, and this month in Stats');
    expect(colour('12', 'cards'), isNot(kit.activity), reason: 'one figure in colour, not all');
    // A circle round each day, today last: today's, the best of the seven, is the largest; days without reading are empty rings.
    expect(find.byType(DayCircle), findsNWidgets(7));
    expect(find.bySemanticsLabel(RegExp(r', today: 30 minutes, 12 cards$')), findsOneWidget);
    double width(int i) => tester.getSize(find.descendant(of: find.byType(DayCircle).at(i), matching: find.byType(AnimatedContainer))).width;
    expect(width(6), DayCircle.largest);
    expect(width(5), DayCircle.smallest);
    expect(find.textContaining('Today  ·  30 min', findRichText: true), findsOneWidget);
    // Tap another day: its figures, with a tap you can feel.
    final haptics = recordHaptics(tester);
    final now = DateTime.now();
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    await tester.tap(find.byType(DayCircle).at(5));
    await tester.pumpAndSettle();
    expect(find.textContaining('${localDate('EEEE').format(yesterday)} ${localDate('MMMd').format(yesterday)}  ·  0 min', findRichText: true), findsOneWidget);
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
    // No books yet; one liked quote (a highlight stays in the Notebook).
    await scrollTo(find.text('No books yet'));
    await scrollTo(find.text('Our life is frittered away by detail.'));
    expect(find.text('Liked quotes'), findsOneWidget);
    expect(find.text('Simplify, simplify.'), findsNothing);
    expect(find.text('View all 1'), findsNothing, reason: 'nothing more to show');
  });

  testWidgets('liked quotes: the newest first, two rows, then every one with View all', (tester) async {
    for (var i = 1; i <= 8; i++) {
      c.read(notebookProvider.notifier).like('b', 'c0.b$i.s0',
          quote: LikedQuote(
              bookId: 'b', sid: 'c0.b$i.s0', bookTitle: 'Walden', author: 'Thoreau', chapterTitle: 'Economy', text: 'Quote $i', likedAt: DateTime(2026, 11, i)));
    }
    c.read(notebookProvider.notifier).like('b', 'c0.b9.s0'); // from before words were kept
    await open(tester);
    Future<void> scrollTo(Finder f) => tester.scrollUntilVisible(f, 300, scrollable: find.byType(Scrollable).first);
    await scrollTo(find.text('View all 8'));
    Iterable<String> shown() => find.textContaining(RegExp(r'^Quote \d$')).evaluate().map((e) => (e.widget as Text).data!);
    expect(shown(), ['Quote 8', 'Quote 7', 'Quote 6', 'Quote 5', 'Quote 4', 'Quote 3'], reason: 'two rows, the newest first');
    expect(find.bySemanticsLabel('Quote 8. Walden'), findsOneWidget);

    await tester.tap(find.text('View all 8'));
    await tester.pumpAndSettle();
    expect(shown(), hasLength(8), reason: 'all of them, in place');
    await scrollTo(find.text('Show less'));
    await tester.tap(find.text('Show less'));
    await tester.pumpAndSettle();
    expect(shown(), hasLength(6));
  });

  testWidgets('no liked quotes yet: how to get one', (tester) async {
    await open(tester);
    await tester.scrollUntilVisible(find.text('No liked quotes yet'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Double-tap a reel you love, and its words show up here.'), findsOneWidget);
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

  testWidgets('older weeks: back a week at a time with the arrows or a swipe, as far as the first day read', (tester) async {
    final now = DateTime.now();
    DateTime ago(int days) => DateTime(now.year, now.month, now.day - days);
    store.saveDoc(
      'habit',
      HabitState(stats: {
        dateKey(now): const DailyStat(verifiedCards: 12, minutes: 30, words: 1450),
        dateKey(ago(9)): const DailyStat(verifiedCards: 8, minutes: 20, words: 900),
      }).toJson(),
    );
    await open(tester);
    final short = localDate('MMMd');
    Finder button(String label) => find.bySemanticsLabel(label);
    bool enabled(String label) => tester.getSemantics(button(label)).flagsCollection.isEnabled == Tristate.isTrue;
    expect(find.text('Last 7 days'), findsOneWidget);
    expect(enabled('Newer days'), isFalse, reason: 'nothing after today');
    expect(enabled('Older days'), isTrue);

    await tester.tap(button('Older days'));
    await tester.pumpAndSettle();
    expect(find.text('${short.format(ago(13))} – ${short.format(ago(7))}'), findsOneWidget);
    expect(figure('20', 'minutes'), findsOneWidget, reason: 'that week’s reading');
    expect(enabled('Older days'), isFalse, reason: 'the first day read is in this week');
    expect(find.bySemanticsLabel(RegExp(r', today')), findsNothing);

    // A swipe across the days goes back to the newer week.
    await tester.fling(find.byType(DayCircle).at(3), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('Last 7 days'), findsOneWidget);
    expect(figure('30', 'minutes'), findsOneWidget);
    // And the other way, to the older one.
    await tester.fling(find.byType(DayCircle).at(3), const Offset(300, 0), 1000);
    await tester.pumpAndSettle();
    expect(figure('20', 'minutes'), findsOneWidget);
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
