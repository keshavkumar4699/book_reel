import 'dart:io';

import 'package:book_reel/data/api_client.dart';
import 'package:book_reel/data/json_store.dart';
import 'package:book_reel/data/store_provider.dart';
import 'package:book_reel/features/friends/friends_screen.dart';
import 'package:book_reel/data/settings.dart';
import 'package:book_reel/ui/kit.dart';
import 'package:book_reel/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../data/fake_server.dart';

void main() {
  testWidgets('Friends tab shows invite code, league, friends and feed with kudos', (tester) async {
    final dir = Directory.systemTemp.createTempSync('bookreel_friends');
    final server = FakeServer();
    late JsonStore store;
    await tester.runAsync(() async => store = await JsonStore.open(dir));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        storeProvider.overrideWithValue(store),
        apiProvider.overrideWithValue(BookReelApi(baseUrl: 'http://fake', deviceId: 'dev1', httpClient: server.client)),
      ],
      child: MaterialApp(theme: buildAppTheme(Kit.forScene(Vibe.forest, ReadingTheme.of(ReadingThemeId.paper))), home: const FriendsScreen()),
    ));
    for (var i = 0; i < 20 && find.text('7PA756JQ').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(find.text('7PA756JQ'), findsOneWidget);
    expect(find.text('Silver league'), findsOneWidget);
    expect(find.text('Asha (you)'), findsWidgets);
    await tester.scrollUntilVisible(find.text('Ravi finished Walden 📚'), 200);
    expect(find.text('👏 2'), findsOneWidget);
    await tester.ensureVisible(find.text('👏 2'));
    await tester.pump();
    await tester.tap(find.text('👏 2'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(find.text('👏 3'), findsOneWidget);
    expect(server.kudos, ['f1']);
    await tester.runAsync(() async => dir.deleteSync(recursive: true));
  });

  testWidgets('Friends tab explains what is needed when no server is configured', (tester) async {
    final dir = Directory.systemTemp.createTempSync('bookreel_friends_off');
    late JsonStore store;
    await tester.runAsync(() async => store = await JsonStore.open(dir));
    await tester.pumpWidget(ProviderScope(
      overrides: [storeProvider.overrideWithValue(store)],
      child: const MaterialApp(home: FriendsScreen()),
    ));
    expect(find.text('Friends and leagues need the BookReel server'), findsOneWidget);
    await tester.runAsync(() async => dir.deleteSync(recursive: true));
  });
}
