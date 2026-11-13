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

  /// Today: 30 minutes, 12 cards. A day last year: 100 minutes, 40 cards.
  void readingHistory() {
    final now = DateTime.now();
    store.saveDoc(
      'habit',
      HabitState(
        stats: {
          dateKey(now): const DailyStat(verifiedCards: 12, minutes: 30),
          dateKey(DateTime(now.year - 1, 6, 3)): const DailyStat(verifiedCards: 40, minutes: 100),
        },
        streak: StreakState(current: 5, best: 9, lastGoalDate: dateKey(now)),
      ).toJson(),
    );
  }

  Finder figure(String value, String label) => find.bySemanticsLabel('$value $label');

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
    // This week: today's reading only.
    expect(figure('30', 'minutes'), findsOneWidget);
    expect(figure('12', 'cards'), findsNWidgets(2), reason: 'this week, and this year in Stats');
    expect(find.bySemanticsLabel(RegExp(r'^Minutes read each day this week: .*30')), findsOneWidget);
    // Streak.
    await scrollTo(find.text('Last 12 weeks'));
    expect(figure('5', 'day streak'), findsOneWidget);
    expect(figure('9', 'best'), findsOneWidget);
    expect(find.text('Last 12 weeks'), findsOneWidget);
    // Stats: this year, then all time.
    await scrollTo(find.text('All time'));
    expect(figure('30 min', 'reading time'), findsOneWidget);
    expect(figure('1', 'reading day'), findsOneWidget);
    await tester.ensureVisible(find.text('All time'));
    await tester.tap(find.text('All time'));
    await tester.pumpAndSettle();
    expect(figure('2 h 10 min', 'reading time'), findsOneWidget);
    expect(figure('52', 'cards'), findsOneWidget);
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
