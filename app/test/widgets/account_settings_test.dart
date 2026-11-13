import 'dart:io';

import 'package:book_reel/data/api_client.dart';
import 'package:book_reel/data/json_store.dart';
import 'package:book_reel/data/segments.dart' show deviceIdProvider;
import 'package:book_reel/data/settings_provider.dart';
import 'package:book_reel/data/store_provider.dart';
import 'package:book_reel/features/settings/settings_screen.dart';
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

  Future<ProviderContainer> open(WidgetTester tester, FakeServer? server) async {
    tester.view.physicalSize = const Size(1236, 4400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('account_settings');
    dirs.add(dir);
    late ProviderContainer c;
    await tester.runAsync(() async {
      final store = await JsonStore.open(dir);
      c = ProviderContainer(overrides: [
        storeProvider.overrideWithValue(store),
        if (server != null)
          apiProvider.overrideWith((ref) => BookReelApi(
                baseUrl: ref.watch(settingsProvider.select((s) => s.online)) ? 'http://fake' : '',
                deviceId: ref.watch(deviceIdProvider),
                httpClient: server.client,
              )),
      ]);
    });
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(theme: buildAppTheme(Kit.appLight), home: const SettingsScreen()),
    ));
    await tester.pumpAndSettle();
    return c;
  }

  testWidgets('Settings → You: delete account asks first, then erases it and turns online features off', (tester) async {
    final server = FakeServer();
    final c = await open(tester, server);
    expect(find.text('Download my data'), findsOneWidget);
    final oldId = c.read(deviceIdProvider);

    // Cancel: nothing happens.
    await tester.ensureVisible(find.text('Delete account'));
    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
    expect(find.text('Delete your account?'), findsOneWidget);
    expect(find.textContaining('books and notes stay on this phone'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(server.deletedAccounts, isEmpty);

    // Delete.
    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    for (var i = 0; i < 50 && find.text('Your account is deleted').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(find.text('Your account is deleted'), findsOneWidget);
    expect(server.deletedAccounts, [oldId]);
    expect(c.read(settingsProvider).online, isFalse);
    expect(find.text('Delete account'), findsNothing, reason: 'no account online any more');
    expect(find.text('Download my data'), findsOneWidget, reason: 'this phone’s data can still be downloaded');
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('If the server can’t be reached, nothing is deleted and you are told', (tester) async {
    final server = FakeServer()..deleteStatus = 503;
    final c = await open(tester, server);
    await tester.ensureVisible(find.text('Delete account'));
    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    for (var i = 0; i < 50 && find.textContaining('nothing was deleted').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(find.textContaining('nothing was deleted'), findsOneWidget);
    expect(c.read(settingsProvider).online, isTrue);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('Without a server: download my data, no delete', (tester) async {
    await open(tester, null);
    expect(find.text('Download my data'), findsOneWidget);
    expect(find.text('Delete account'), findsNothing);
  });
}
