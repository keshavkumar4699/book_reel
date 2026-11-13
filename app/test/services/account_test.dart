import 'dart:convert';
import 'dart:io';

import 'package:book_reel/data/api_client.dart';
import 'package:book_reel/data/json_store.dart';
import 'package:book_reel/data/notebook.dart';
import 'package:book_reel/data/segments.dart' show deviceIdProvider;
import 'package:book_reel/data/sessions.dart';
import 'package:book_reel/data/settings.dart';
import 'package:book_reel/data/settings_provider.dart';
import 'package:book_reel/data/store_provider.dart';
import 'package:book_reel/services/account.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../data/fake_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(ProviderContainer, JsonStore, Directory)> container({FakeServer? server}) async {
    final dir = Directory.systemTemp.createTempSync('account');
    final store = await JsonStore.open(dir);
    final c = ProviderContainer(overrides: [
      storeProvider.overrideWithValue(store),
      if (server != null)
        apiProvider.overrideWith((ref) => BookReelApi(
              baseUrl: ref.watch(settingsProvider.select((s) => s.online)) ? 'http://fake' : '',
              deviceId: ref.watch(deviceIdProvider),
              httpClient: server.client,
            )),
    ]);
    addTearDown(() async {
      c.dispose();
      await store.flush();
      dir.deleteSync(recursive: true);
    });
    return (c, store, dir);
  }

  void someReading(ProviderContainer c) {
    c.read(settingsProvider.notifier).update((s) => s.copyWith(displayName: 'Asha', bio: 'Classics at dawn'));
    c.read(sessionLogProvider.notifier).record(bookId: 'b1', title: 'Emma', author: 'Jane Austen', dwellMs: 60000, progress: 0.1);
    final nb = c.read(notebookProvider.notifier);
    nb.toggleSaved(SavedCard(
      id: nb.newId(),
      bookId: 'b1',
      bookTitle: 'Emma',
      author: 'Jane Austen',
      chapterTitle: 'Volume I',
      startSid: 's1',
      text: 'Emma Woodhouse, handsome, clever, and rich.',
      createdAt: DateTime(2026, 11, 13),
    ));
  }

  test('download my data, offline: everything on this phone, nothing secret', () async {
    final (c, _, _) = await container();
    someReading(c);
    c.read(deviceIdProvider);
    final d = jsonDecode(await c.read(accountProvider).exportJson(now: DateTime.utc(2026, 11, 13))) as Map<String, dynamic>;
    expect(d['app'], 'Cloro');
    expect(d['exported_at'], '2026-11-13T00:00:00.000Z');
    final phone = d['phone'] as Map<String, dynamic>;
    expect(phone.keys.toSet(), {'settings', 'library', 'notebook', 'habit', 'sessions', 'mood'});
    expect((phone['settings'] as Map)['bio'], 'Classics at dawn');
    expect(jsonEncode(phone['notebook']), contains('Emma Woodhouse'));
    expect(jsonEncode(phone['sessions']), contains('Jane Austen'));
    expect(d['server'], isNull);
    expect(jsonEncode(d), isNot(contains(c.read(deviceIdProvider))), reason: 'the phone’s identity is not in the file');
  });

  test('download my data, online: the server’s copy too', () async {
    final server = FakeServer();
    final (c, _, dir) = await container(server: server);
    someReading(c);
    final file = await c.read(accountProvider).exportFile(dir: dir);
    expect(file.path, matches(RegExp(r'cloro-data-\d{4}-\d{2}-\d{2}\.json$')));
    final d = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    expect((d['server'] as Map)['user'], containsPair('display_name', 'Asha'));
    expect(d['phone'], isNotNull);
    expect(server.sessions, isNotEmpty, reason: 'pending sessions were uploaded first, so the server copy is complete');
  });

  test('delete account: erased on the server; new identity; online features off; books and notes stay', () async {
    final server = FakeServer();
    final (c, store, _) = await container(server: server);
    someReading(c);
    final oldId = c.read(deviceIdProvider);
    await store.saveDoc('sync', {'cursor': 12, 'pushed': {'saved|x': 'abc'}});
    expect(c.read(apiProvider).enabled, isTrue);

    await c.read(accountProvider).deleteAccount();

    expect(server.deletedAccounts, [oldId]);
    expect(c.read(deviceIdProvider), isNot(oldId));
    expect(c.read(settingsProvider).online, isFalse);
    expect(c.read(apiProvider).enabled, isFalse, reason: 'nothing is uploaded again');
    expect(store.doc('sync'), isEmpty);
    expect(c.read(notebookProvider).saved, hasLength(1), reason: 'notes stay on the phone');
    expect(c.read(sessionLogProvider), hasLength(1));

    // Turning online features back on starts a new account under the new identity.
    c.read(settingsProvider.notifier).update((s) => s.copyWith(online: true));
    expect(c.read(apiProvider).enabled, isTrue);
    expect(c.read(apiProvider).deviceId, c.read(deviceIdProvider));
  });

  test('delete account when the server can’t be reached: nothing changes', () async {
    final server = FakeServer()..deleteStatus = 503;
    final (c, _, _) = await container(server: server);
    final oldId = c.read(deviceIdProvider);
    await expectLater(c.read(accountProvider).deleteAccount(), throwsA(isA<ApiException>()));
    expect(c.read(deviceIdProvider), oldId);
    expect(c.read(settingsProvider).online, isTrue);
  });

  test('online features: a saved setting, on by default', () {
    expect(const AppSettings().online, isTrue);
    expect(AppSettings.fromJson(const AppSettings().copyWith(online: false).toJson()).online, isFalse);
  });
}
