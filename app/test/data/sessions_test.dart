import 'dart:io';

import 'package:book_reel/data/api_client.dart';
import 'package:book_reel/data/json_store.dart';
import 'package:book_reel/data/sessions.dart';
import 'package:book_reel/data/store_provider.dart';
import 'package:book_reel/data/sync_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime now;

  Future<(ProviderContainer, JsonStore)> container({FakeServer? server}) async {
    final dir = Directory.systemTemp.createTempSync('sessions');
    final store = await JsonStore.open(dir);
    final c = ProviderContainer(overrides: [
      storeProvider.overrideWithValue(store),
      apiProvider.overrideWithValue(
          BookReelApi(baseUrl: server == null ? '' : 'http://fake', deviceId: 'dev1', httpClient: server?.client)),
    ]);
    addTearDown(() async {
      c.dispose();
      await store.flush();
      dir.deleteSync(recursive: true);
    });
    c.read(sessionLogProvider.notifier).clock = () => now;
    return (c, store);
  }

  void read(ProviderContainer c, {String book = 'b1', String title = 'Walden', int seconds = 60, double progress = 0.1, String? mood}) =>
      c.read(sessionLogProvider.notifier).record(bookId: book, title: title, author: 'Thoreau', dwellMs: seconds * 1000, progress: progress, mood: mood);

  test('cards in one book, within 30 minutes of each other, are one session', () async {
    now = DateTime(2026, 11, 13, 20);
    final (c, _) = await container();
    read(c, seconds: 90, progress: 0.10, mood: 'cozy');
    now = now.add(const Duration(minutes: 2));
    read(c, seconds: 30, progress: 0.12);
    now = now.add(const Duration(minutes: 29));
    read(c, seconds: 60, progress: 0.11); // progress never goes back
    var sessions = c.read(sessionLogProvider);
    expect(sessions, hasLength(1));
    final s = sessions.single;
    expect((s.cards, s.progress, s.mood), (3, 0.12, 'cozy'));
    expect(s.minutes, closeTo(3, 0.001));
    expect(s.startedAt, DateTime(2026, 11, 13, 19, 58, 30), reason: 'the first card started when it was shown');

    now = now.add(const Duration(minutes: 31));
    read(c);
    read(c, book: 'b2', title: 'Emma');
    sessions = c.read(sessionLogProvider);
    expect(sessions.map((s) => (s.title, s.cards)), [('Walden', 3), ('Walden', 1), ('Emma', 1)]);
  });

  test('a saved line goes on the open session, cut to 280 characters at a word', () async {
    now = DateTime(2026, 11, 13, 20);
    final (c, _) = await container();
    final log = c.read(sessionLogProvider.notifier);
    log.quote('b1', 'No session yet');
    expect(c.read(sessionLogProvider), isEmpty);
    read(c);
    log.quote('b2', 'Another book');
    expect(c.read(sessionLogProvider).single.quote, isNull);
    log.quote('b1', 'I went to the woods because I wished to live deliberately. ' * 8);
    final q = c.read(sessionLogProvider).single.quote!;
    expect(q.length, lessThanOrEqualTo(280));
    expect(q, endsWith('…'));
    expect(q, startsWith('I went to the woods'));
  });

  test('what is uploaded: the stats, the title and author, the mood and line; nothing else', () async {
    now = DateTime(2026, 11, 13, 20);
    final (c, _) = await container();
    read(c, mood: 'calm');
    c.read(sessionLogProvider.notifier).quote('b1', 'A line.');
    final up = c.read(sessionLogProvider).single.toUpload();
    expect(up.keys.toSet(), {'client_id', 'started_at', 'minutes', 'cards', 'book', 'progress', 'mood', 'quote'});
    expect(up['book'], {'title': 'Walden', 'author': 'Thoreau'});
    expect(up['client_id'], matches(RegExp(r'^[A-Za-z0-9_-]{8,64}$')));
    expect(up['started_at'], endsWith('Z'));
  });

  test('sync uploads each session, and again as it grows; the log survives a restart', () async {
    now = DateTime(2026, 11, 13, 20);
    final server = FakeServer();
    final (c, store) = await container(server: server);
    read(c, mood: 'calm');
    final sync = c.read(syncServiceProvider);
    await sync.flushSessions();
    final id = c.read(sessionLogProvider).single.id;
    expect(server.sessions[id], containsPair('cards', 1));
    expect(c.read(sessionLogProvider.notifier).pending, isEmpty);

    now = now.add(const Duration(minutes: 1));
    read(c);
    expect(c.read(sessionLogProvider.notifier).pending, hasLength(1));
    await sync.flushSessions();
    expect(server.sessions, hasLength(1), reason: 'the same card, updated');
    expect(server.sessions[id], containsPair('cards', 2));

    // A session that grew while it was being sent stays pending.
    final sent = c.read(sessionLogProvider).single;
    read(c);
    c.read(sessionLogProvider.notifier).markUploaded(sent);
    expect(c.read(sessionLogProvider.notifier).pending, hasLength(1));

    final again = ProviderContainer(overrides: [storeProvider.overrideWithValue(store)]);
    addTearDown(again.dispose);
    expect(again.read(sessionLogProvider).single.cards, 3);
  });
}
