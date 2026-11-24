import 'dart:io';

import 'package:book_reel/data/api_client.dart';
import 'package:book_reel/data/habit.dart';
import 'package:book_reel/data/json_store.dart';
import 'package:book_reel/data/sessions.dart';
import 'package:book_reel/data/settings_provider.dart';
import 'package:book_reel/data/store_provider.dart';
import 'package:book_reel/features/journal/feed.dart';
import 'package:book_reel/features/journal/journal_screen.dart';
import 'package:book_reel/ui/kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../data/fake_server.dart';

void main() {
  // Stores finish writing in the background: their folders go at the end.
  final dirs = <Directory>[];
  tearDownAll(() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final d in dirs) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
  });

  Future<ProviderContainer> open(WidgetTester tester, {FakeServer? server, void Function(ProviderContainer c)? before}) async {
    tester.view.physicalSize = const Size(1236, 2745);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('today');
    dirs.add(dir);
    late ProviderContainer c;
    await tester.runAsync(() async {
      final store = await JsonStore.open(dir);
      c = ProviderContainer(overrides: [
        storeProvider.overrideWithValue(store),
        apiProvider.overrideWithValue(
            BookReelApi(baseUrl: server == null ? '' : 'http://fake', deviceId: 'dev1', httpClient: server?.client)),
      ]);
      c.read(settingsProvider.notifier).update((s) => s.copyWith(onboardingDone: true, goalSetupDone: true, displayName: 'Asha'));
      before?.call(c);
    });
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(theme: buildAppTheme(Kit.appLight), home: const JournalScreen()),
    ));
    return c;
  }

  Future<void> settle(WidgetTester tester, Finder until) async {
    for (var i = 0; i < 100 && until.evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
    expect(until, findsWidgets);
  }

  void readALittle(ProviderContainer c) {
    final log = c.read(sessionLogProvider.notifier);
    for (var i = 0; i < 4; i++) {
      log.record(bookId: 'b1', title: 'Emma', author: 'Jane Austen', dwellMs: 45000, progress: 0.2);
    }
  }

  testWidgets('the feed: sessions with their stats, milestones, kudos and comments', (tester) async {
    final server = FakeServer();
    final c = await open(tester, server: server, before: readALittle);
    await settle(tester, find.text('Walden'));

    // Ravi's session: the book, the stats and the line he saved (moods are gone, even from older apps).
    expect(find.text('Ravi'), findsWidgets);
    expect(find.text('Henry David Thoreau'), findsOneWidget);
    expect(find.text('34 min'), findsOneWidget);
    expect(find.text('21'), findsOneWidget);
    expect(find.text('41%'), findsOneWidget);
    expect(find.text('😌 Calm'), findsNothing);
    expect(find.textContaining('live deliberately'), findsOneWidget);
    // Your session went up to the feed before it loaded.
    final mine = c.read(sessionLogProvider).single;
    expect(server.sessions[mine.id], containsPair('cards', 4));

    // Kudos: once, shown at once.
    await tester.ensureVisible(find.text('👏 2'));
    await tester.pump();
    await tester.tap(find.text('👏 2'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(find.text('👏 3'), findsOneWidget);
    expect(server.kudos, ['f1']);

    // Comments: read them, add one.
    await tester.tap(find.bySemanticsLabel('1 comment. Open'));
    await settle(tester, find.text('Such a calm book.'));
    await tester.ensureVisible(find.text('Add a comment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add a comment'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Adding it to my list!');
    await tester.tap(find.text('Post'));
    await settle(tester, find.text('Adding it to my list!'));
    expect(server.comments['f1']!.map((x) => x['text']), ['Such a calm book.', 'Adding it to my list!']);
    tester.state<NavigatorState>(find.byType(Navigator).last).pop(); // close the sheet
    await tester.pump(const Duration(seconds: 3)); // toasts and sheets settle
    await tester.pumpAndSettle();

    // His finished book, as a milestone, further down.
    await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('Finished Walden'), findsOneWidget);
  });

  testWidgets('offline: your own reading sessions, without kudos or comments', (tester) async {
    await open(tester, before: readALittle);
    await settle(tester, find.text('Emma'));
    expect(find.text('You'), findsOneWidget);
    expect(find.text('Jane Austen'), findsOneWidget);
    expect(find.text('3 min'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('20%'), findsOneWidget);
    expect(find.text('Mood'), findsNothing, reason: 'moods are gone');
    expect(find.textContaining('👏'), findsNothing);
  });

  testWidgets('your progress, shared any time: today, the last 7 days or all time', (tester) async {
    await open(tester, before: (c) {
      for (var i = 0; i < 6; i++) {
        c.read(habitProvider.notifier).recordCard(words: 160, dwellMs: 45000);
      }
    });
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Share your progress'));
    await tester.pumpAndSettle();
    expect(find.text('Share your progress'), findsOneWidget, reason: 'the sheet’s title');
    expect(find.text('Today’s reading'), findsOneWidget, reason: 'read today: today first');
    expect(find.text('Reading Alice’s Adventures in Wonderland · page 1 of 97'), findsNothing);
    expect(find.text('CARDS'), findsOneWidget);
    expect(find.text('6'), findsOneWidget, reason: 'six cards read today');
    expect(find.text('PAGES'), findsOneWidget);
    expect(find.text('DAY STREAK'), findsOneWidget);

    await tester.tap(find.text('Last 7 days'));
    await tester.pumpAndSettle();
    expect(find.text('My week of reading'), findsOneWidget);
    expect(find.text('1/7'), findsOneWidget, reason: 'one day read this week');
    await tester.tap(find.text('All time'));
    await tester.pumpAndSettle();
    expect(find.text('My reading so far'), findsOneWidget);
    expect(find.text('BEST STREAK'), findsOneWidget);
  });

  testWidgets('the server can’t be reached: your own reading, and a way to try again', (tester) async {
    final server = FakeServer()..feedStatus = 503;
    await open(tester, server: server, before: readALittle);
    await settle(tester, find.text('Emma'));
    expect(find.text('Can’t reach Cloro right now'), findsOneWidget);
    expect(find.text('You'), findsOneWidget, reason: 'your sessions, from the phone');
    server.feedStatus = 200;
    await tester.tap(find.bySemanticsLabel('Try again'));
    await settle(tester, find.text('Ravi'));
    expect(find.text('Can’t reach Cloro right now'), findsNothing);
  });

  testWidgets('older activity loads as you reach the end', (tester) async {
    final server = FakeServer();
    final start = DateTime.now().toUtc();
    server.feed
      ..clear()
      ..addAll([
        for (var i = 0; i < 25; i++)
          {
            'id': 'p$i',
            'userId': 'device:ravi',
            'type': 'session',
            'text': 'Ravi read Book $i',
            'at': start.subtract(Duration(hours: i + 1)).toIso8601String(),
            'data': {'book': {'title': 'Book $i', 'author': ''}, 'minutes': 5, 'cards': 3, 'progress': 0},
            'author': {'name': 'Ravi', 'handle': 'ravi', 'avatar': '🦊'},
            'kudos': 0,
            'gaveKudos': false,
            'comments': 0,
            'mine': false,
          },
      ]);
    final c = await open(tester, server: server);
    await settle(tester, find.text('Book 0'));
    expect(c.read(journalFeedProvider).value!.items, hasLength(20));
    expect(c.read(journalFeedProvider).value!.more, isTrue);
    // Reaching the end of the list loads the next page.
    for (var i = 0; i < 40 && c.read(journalFeedProvider).value!.items.length < 25; i++) {
      await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -600));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
    expect(c.read(journalFeedProvider).value!.items, hasLength(25));
    expect(c.read(journalFeedProvider).value!.more, isFalse);
  });

  test('time ago', () {
    final now = DateTime(2026, 11, 13, 21);
    expect(timeAgo(now.subtract(const Duration(seconds: 20)), now), 'now');
    expect(timeAgo(now.subtract(const Duration(minutes: 5)), now), '5 min');
    expect(timeAgo(now.subtract(const Duration(hours: 3)), now), '3 h');
    expect(timeAgo(DateTime(2026, 11, 12, 23), now), 'Yesterday');
    expect(timeAgo(DateTime(2026, 11, 10, 9), now), 'Tue');
    expect(timeAgo(DateTime(2026, 10, 2, 9), now), '2 Oct');
    expect(timeAgo(DateTime(2025, 10, 2, 9), now), '2 Oct 2025');
  });
}
