import 'dart:io';

import 'package:book_reel/data/api_client.dart';
import 'package:book_reel/data/json_store.dart';
import 'package:book_reel/data/settings_provider.dart';
import 'package:book_reel/data/store_provider.dart';
import 'package:book_reel/features/settings/settings_screen.dart';
import 'package:book_reel/features/social/reader_profile_screen.dart';
import 'package:book_reel/features/social/safety.dart';
import 'package:book_reel/features/today/today_screen.dart';
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

  Future<ProviderContainer> open(WidgetTester tester, FakeServer server, Widget home) async {
    tester.view.physicalSize = const Size(1236, 4000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('safety');
    dirs.add(dir);
    late ProviderContainer c;
    await tester.runAsync(() async {
      final store = await JsonStore.open(dir);
      c = ProviderContainer(overrides: [
        storeProvider.overrideWithValue(store),
        apiProvider.overrideWithValue(BookReelApi(baseUrl: 'http://fake', deviceId: 'dev1', httpClient: server.client)),
      ]);
      c.read(settingsProvider.notifier).update((s) => s.copyWith(onboardingDone: true, goalSetupDone: true, displayName: 'Asha'));
    });
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: MaterialApp(theme: buildAppTheme(Kit.appLight), home: home)));
    return c;
  }

  Future<void> until(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 100 && f.evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(f, findsWidgets);
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(text).last);
    await tester.pumpAndSettle();
  }

  testWidgets('block a reader from their profile: asked first, then done', (tester) async {
    final server = FakeServer();
    await open(tester, server, const ReaderProfileScreen(id: '@ravi'));
    await until(tester, find.text('Slow reader, fast walker'));
    await tester.tap(find.bySemanticsLabel('More: report or block'));
    await tester.pumpAndSettle();
    expect(find.text('Report Ravi'), findsOneWidget);
    await tapText(tester, 'Block Ravi');
    expect(find.text('Block Ravi?'), findsOneWidget);
    expect(find.textContaining('They aren’t told'), findsOneWidget);
    await tapText(tester, 'Block');
    await until(tester, find.text('Ravi is blocked'));
    expect(server.blocked, {'device:ravi'});
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('report a post in the feed: pick a reason, it is sent', (tester) async {
    final server = FakeServer();
    await open(tester, server, const TodayScreen());
    await until(tester, find.text('Walden'));
    await tester.tap(find.bySemanticsLabel('More: report or block').first);
    await tester.pumpAndSettle();
    await tapText(tester, 'Report post');
    expect(find.text('Report this post'), findsOneWidget);
    await tapText(tester, 'Spam');
    await until(tester, find.textContaining('We’ll take a look'));
    expect(server.reports, [
      {'type': 'activity', 'id': 'f1', 'reason': 'spam', 'note': ''},
    ]);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('a comment the server refuses says why: links, or too many too fast', (tester) async {
    final server = FakeServer();
    await open(tester, server, const TodayScreen());
    await until(tester, find.text('Walden'));
    Future<void> comment(String text) async {
      await tester.tap(find.bySemanticsLabel('1 comment. Open'));
      await until(tester, find.text('Such a calm book.'));
      await tapText(tester, 'Add a comment');
      await tester.enterText(find.byType(TextField), text);
      await tester.tap(find.text('Post'));
      await tester.pump();
    }

    await comment('See http://spam.example');
    await until(tester, find.text('Links aren\'t allowed here.'));
    await tester.pump(const Duration(seconds: 3));
    tester.state<NavigatorState>(find.byType(Navigator).last).pop();
    await tester.pumpAndSettle();

    server.commentsRateLimited = true;
    await comment('Lovely');
    await until(tester, find.text('That’s a lot at once. Try again in a minute.'));
    expect(server.comments['f1'], hasLength(1), reason: 'nothing was added');
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('Settings → Blocked readers: see them and unblock', (tester) async {
    final server = FakeServer()..blocked.add('device:meera');
    await open(tester, server, const SettingsScreen());
    await tester.pumpAndSettle();
    await tapText(tester, 'Blocked readers');
    await until(tester, find.text('Meera'));
    expect(find.text('@meera.reads'), findsOneWidget);
    await tapText(tester, 'Unblock');
    await until(tester, find.text('You haven’t blocked anyone.'));
    expect(server.blocked, isEmpty);
  });

  test('error messages', () {
    expect(apiErrorMessage(ApiException(429, '{"error":"rate_limited"}')), 'That’s a lot at once. Try again in a minute.');
    expect(apiErrorMessage(ApiException(400, '{"error":"not_allowed","message":"Links aren\'t allowed here."}')), 'Links aren\'t allowed here.');
    expect(apiErrorMessage(ApiException(500, 'oops'), fallback: 'x'), 'x');
    expect(apiErrorMessage(const SocketException('down')), contains('connection'));
  });
}
