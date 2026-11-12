import 'dart:io';

import 'package:book_reel/data/api_client.dart';
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

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('profile');
    server = FakeServer()..takenHandles.add('taken.name');
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

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1236, 2745);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(theme: buildAppTheme(Kit.forScene(Vibe.night, ReadingTheme.of(ReadingThemeId.paper))), home: const ProfileScreen()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('profile shows who you are, your numbers and your quotes', (tester) async {
    c.read(settingsProvider.notifier).update((s) => s.copyWith(
        displayName: 'Asha', username: 'asha.reads', pronouns: 'she/her', bio: 'Classics on the commute.', interests: ['Fantasy']));
    c.read(notebookProvider.notifier).addHighlight(bookId: 'b', bookTitle: 'Walden', sid: 'c0.b0.s0', text: 'Simplify, simplify.');
    await open(tester);
    expect(find.text('@asha.reads'), findsOneWidget, reason: 'in the top bar');
    expect(find.textContaining('she/her', findRichText: true), findsOneWidget);
    expect(find.text('Classics on the commute.'), findsOneWidget);
    expect(find.text('Fantasy'), findsOneWidget);
    expect(find.text('saved'), findsOneWidget);
    expect(find.text('Simplify, simplify.'), findsOneWidget, reason: 'quotes grid');
    await tester.tap(find.text('Stats'));
    await tester.pumpAndSettle();
    expect(find.text('LAST 12 WEEKS'), findsOneWidget);
  });

  testWidgets('edit profile: a taken or malformed username is refused; the rest is saved', (tester) async {
    await open(tester);
    await tester.tap(find.text('Edit profile'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Asha');
    await tester.enterText(fields.at(1), 'Not Valid!');
    await tester.enterText(fields.at(3), 'Reading my way through the classics.');
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
