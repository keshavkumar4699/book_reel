import 'dart:io';

import 'package:book_reel/data/api_client.dart';
import 'package:book_reel/data/json_store.dart';
import 'package:book_reel/data/settings.dart';
import 'package:book_reel/data/store_provider.dart';
import 'package:book_reel/features/social/people_screen.dart';
import 'package:book_reel/features/social/reader_profile_screen.dart';
import 'package:book_reel/ui/kit.dart';
import 'package:book_reel/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../data/fake_server.dart';

void main() {
  late Directory dir;
  late ProviderContainer c;
  late FakeServer server;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('people');
    server = FakeServer();
    final store = await JsonStore.open(dir);
    c = ProviderContainer(overrides: [
      storeProvider.overrideWithValue(store),
      apiProvider.overrideWithValue(BookReelApi(baseUrl: 'http://fake', deviceId: 'dev1', httpClient: server.client)),
    ]);
  });

  tearDown(() {
    c.dispose();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<GoRouter> open(WidgetTester tester, String location) async {
    tester.view.physicalSize = const Size(1236, 2745);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final router = GoRouter(initialLocation: location, routes: [
      GoRoute(
        path: '/people/:userId',
        builder: (_, s) => PeopleScreen(
          userId: s.pathParameters['userId']!,
          tab: s.uri.queryParameters['tab'] == 'following' ? PeopleTab.following : PeopleTab.followers,
          name: s.uri.queryParameters['name'],
        ),
      ),
      GoRoute(path: '/u/:id', builder: (_, s) => ReaderProfileScreen(id: s.pathParameters['id']!)),
      GoRoute(path: '/profile', builder: (_, _) => const Text('your profile')),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp.router(theme: buildAppTheme(Kit.forScene(Vibe.night, ReadingTheme.of(ReadingThemeId.paper))), routerConfig: router),
    ));
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('your followers: follow back from the list, and the server knows', (tester) async {
    await open(tester, '/people/me');
    expect(find.text('Followers'), findsOneWidget);
    expect(find.text('Ravi'), findsOneWidget);
    expect(find.text('@ravi'), findsOneWidget);
    expect(find.text('7PA756JQ'), findsOneWidget, reason: 'your invite, under your lists');

    await tester.tap(find.widgetWithText(KitButton, 'Follow'));
    await tester.pumpAndSettle();
    expect(server.following, {'device:ravi'});
    expect(find.widgetWithText(KitButton, 'Following'), findsOneWidget);

    // Unfollow from the Following tab.
    await tester.tap(find.text('Following').first);
    await tester.pumpAndSettle();
    expect(find.text('Ravi'), findsOneWidget);
    await tester.tap(find.widgetWithText(KitButton, 'Following'));
    await tester.pumpAndSettle();
    expect(server.following, isEmpty);
    expect(find.widgetWithText(KitButton, 'Follow'), findsOneWidget);
  });

  testWidgets('find people by @username', (tester) async {
    await open(tester, '/people/me?tab=following');
    expect(find.textContaining('You don’t follow anyone yet'), findsOneWidget);

    await tester.tap(find.text('Find people'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '@nobody');
    await tester.tap(find.text('Follow').last);
    await tester.pumpAndSettle();
    expect(find.text('No reader is called @nobody.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Find people'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '@Meera.Reads');
    await tester.tap(find.text('Follow').last);
    await tester.pumpAndSettle();
    expect(server.following, {'device:meera'});
    expect(find.text('You now follow Meera'), findsOneWidget);
    expect(find.text('Meera'), findsOneWidget, reason: 'now in your Following list');
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('another reader’s profile: header, Follows you, streak, Follow', (tester) async {
    await open(tester, '/u/device:ravi');
    expect(find.text('@ravi'), findsOneWidget, reason: 'title');
    expect(find.textContaining('he/him', findRichText: true), findsOneWidget);
    expect(find.text('Slow reader, fast walker'), findsOneWidget);
    expect(find.textContaining('Walden', findRichText: true), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Follows you'), findsOneWidget);
    expect(find.text('12-day streak'), findsOneWidget);
    expect(find.text('0 followers'), findsOneWidget);

    await tester.tap(find.widgetWithText(KitButton, 'Follow'));
    await tester.pumpAndSettle();
    expect(server.following, {'device:ravi'});
    expect(find.text('1 follower'), findsOneWidget);
    expect(find.widgetWithText(KitButton, 'Following'), findsOneWidget);
  });

  testWidgets('an unknown reader, and the lists offline', (tester) async {
    await open(tester, '/u/@nobody');
    expect(find.text('No reader found'), findsOneWidget);
  });
}
