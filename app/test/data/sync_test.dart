import 'dart:io';

import 'package:book_reel/data/api_client.dart';
import 'package:book_reel/data/habit.dart';
import 'package:book_reel/data/json_store.dart';
import 'package:book_reel/data/library.dart';
import 'package:book_reel/data/notebook.dart';
import 'package:book_reel/data/settings_provider.dart';
import 'package:book_reel/data/store_provider.dart';
import 'package:book_reel/data/sync_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dirs = <Directory>[];
  final containers = <ProviderContainer>[];

  /// A "device": its own local store, talking to [server] as [user].
  Future<ProviderContainer> device(FakeServer server, String user) async {
    final dir = await Directory.systemTemp.createTemp('bookreel_sync');
    dirs.add(dir);
    final c = ProviderContainer(overrides: [
      storeProvider.overrideWithValue(await JsonStore.open(dir)),
      apiProvider.overrideWithValue(BookReelApi(baseUrl: 'http://fake', deviceId: user, httpClient: server.client)),
    ]);
    containers.add(c);
    return c;
  }

  tearDown(() async {
    for (final c in containers) {
      c.dispose();
    }
    containers.clear();
    for (final d in dirs) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
    dirs.clear();
  });

  test('notebook changes and deletions reach another device of the same account', () async {
    final server = FakeServer();
    // Two phones signed in to the same account share one server-side user.
    final a = await device(server, 'acct');
    final b = await device(server, 'acct');

    final h = a.read(notebookProvider.notifier).toggleHighlight(bookId: 'bk', bookTitle: 'Walden', sid: 'c0.b0.s0', text: 'Simplify.');
    a.read(notebookProvider.notifier).addWord(word: 'sanguine', meaning: 'hopeful', sentence: 's', bookTitle: 'Walden');
    await a.read(syncServiceProvider).syncNow();

    await b.read(syncServiceProvider).syncNow();
    expect(b.read(notebookProvider).highlights.single.text, 'Simplify.');
    expect(b.read(notebookProvider).hasWord('sanguine'), isTrue);

    // B removes the highlight and adds a note elsewhere; A learns both.
    b.read(notebookProvider.notifier).removeHighlight(h!.id);
    b.read(notebookProvider.notifier).addReflection(bookTitle: 'Walden', chapterTitle: 'Economy', text: 'Own less.');
    await b.read(syncServiceProvider).syncNow();
    await a.read(syncServiceProvider).syncNow();
    expect(a.read(notebookProvider).highlights, isEmpty);
    expect(a.read(notebookProvider).reflections.single.text, 'Own less.');

    // A second pass with no changes sends nothing new.
    final before = server.seq;
    await a.read(syncServiceProvider).syncNow();
    expect(server.seq, before);
  });

  test('a local edit made before pulling is kept and pushed', () async {
    final server = FakeServer();
    final a = await device(server, 'acct');
    final b = await device(server, 'acct');
    final h = a.read(notebookProvider.notifier).toggleHighlight(bookId: 'bk', bookTitle: 'T', sid: 's', text: 't')!;
    await a.read(syncServiceProvider).syncNow();
    await b.read(syncServiceProvider).syncNow();

    a.read(notebookProvider.notifier).updateHighlight(h.copyWith(note: 'from A'));
    await a.read(syncServiceProvider).syncNow();
    b.read(notebookProvider.notifier).updateHighlight(h.copyWith(note: 'from B (later)'));
    await b.read(syncServiceProvider).syncNow(); // pulls A's edit but keeps its own newer edit
    await a.read(syncServiceProvider).syncNow();
    expect(b.read(notebookProvider).highlights.single.note, 'from B (later)');
    expect(a.read(notebookProvider).highlights.single.note, 'from B (later)');
  });

  test('reading events are queued, uploaded once, and the profile is sent', () async {
    final server = FakeServer();
    final a = await device(server, 'dev1');
    a.read(settingsProvider.notifier).update((s) => s.copyWith(displayName: 'Asha', dailyGoal: 5));
    final habit = a.read(habitProvider.notifier);
    habit.recordCard(words: 120, dwellMs: 30000, bookId: 'bk', cardRef: 'bk:c0.b0.s0');
    habit.recordCard(words: 120, dwellMs: 30000, bookId: 'bk', cardRef: 'bk:c0.b2.s0');
    await a.read(syncServiceProvider).syncNow();
    expect(server.activity.map((e) => e['card_ref']), ['bk:c0.b0.s0', 'bk:c0.b2.s0']);
    expect(server.profiles['dev1'], {
      'display_name': 'Asha',
      'daily_goal_cards': 5,
      'freezes_per_week': 1,
      'handle': '',
      'pronouns': '',
      'bio': '',
      'avatar': '',
    });
    await a.read(syncServiceProvider).syncNow();
    expect(server.activity, hasLength(2), reason: 'the outbox is emptied after upload');
  });

  test('profile: username, pronouns, bio and avatar emoji sync; a taken username never blocks syncing', () async {
    final server = FakeServer()..takenHandles.add('taken');
    final a = await device(server, 'dev1');
    a.read(settingsProvider.notifier).update((s) => s.copyWith(username: 'asha.reads', pronouns: 'she/her', bio: 'Classics.', avatarEmoji: '🦉'));
    await a.read(syncServiceProvider).syncNow();
    expect(server.profiles['dev1'], containsPair('handle', 'asha.reads'));
    expect(server.profiles['dev1'], containsPair('bio', 'Classics.'));
    expect(server.profiles['dev1'], containsPair('avatar', '🦉'));
    // Someone took the name in the meantime: the rest still syncs, and reading uploads too.
    a.read(settingsProvider.notifier).update((s) => s.copyWith(username: 'taken', bio: 'Still syncing.'));
    a.read(habitProvider.notifier).recordCard(words: 120, dwellMs: 30000, bookId: 'bk', cardRef: 'bk:c0.b0.s0');
    await a.read(syncServiceProvider).syncNow();
    expect(server.profiles['dev1'], containsPair('bio', 'Still syncing.'));
    expect(server.profiles['dev1'], containsPair('handle', 'asha.reads'));
    expect(server.activity, hasLength(1));
  });

  test('reading positions sync to the device that read less recently', () async {
    final server = FakeServer();
    final a = await device(server, 'acct');
    final b = await device(server, 'acct');
    final metaA = (await a.read(libraryProvider.notifier).ensureStarterBook())!;
    await b.read(libraryProvider.notifier).ensureStarterBook();
    a.read(libraryProvider.notifier).updatePosition(metaA.id, sid: 'c4.b2.s0', progress: 0.4, at: DateTime.now().add(const Duration(minutes: 5)));
    await a.read(syncServiceProvider).syncNow();
    await b.read(syncServiceProvider).syncNow();
    expect(b.read(libraryProvider).single.positionSid, 'c4.b2.s0');
  });

  test('sync is a no-op without a server', () async {
    final dir = await Directory.systemTemp.createTemp('bookreel_nosync');
    dirs.add(dir);
    final c = ProviderContainer(overrides: [storeProvider.overrideWithValue(await JsonStore.open(dir))]);
    containers.add(c);
    expect(c.read(apiProvider).enabled, isFalse);
    await c.read(syncServiceProvider).syncNow(); // must not throw
  });
}
