import 'dart:io';

import 'package:book_reel/core/habit/habit_engine.dart';
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
      // A store write can still land in the folder as it goes: retry once.
      for (var i = 0; i < 2 && d.existsSync(); i++) {
        try {
          d.deleteSync(recursive: true);
        } on FileSystemException {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }
    }
    dirs.clear();
  });

  test('the app syncs every few minutes while open and never in the background, so an idle server can sleep', () async {
    final server = FakeServer();
    final c = await device(server, 'acct');
    final sync = c.read(syncServiceProvider);
    expect(SyncService.every, const Duration(minutes: 5));
    sync.start();
    expect(sync.running, isTrue);
    await sync.syncNow();
    sync.stop(); // the app went to the background
    expect(sync.running, isFalse);
    // Without a server, nothing runs at all.
    final dir = await Directory.systemTemp.createTemp('bookreel_sync');
    dirs.add(dir);
    final offline = ProviderContainer(overrides: [
      storeProvider.overrideWithValue(await JsonStore.open(dir)),
      apiProvider.overrideWithValue(BookReelApi(baseUrl: '', deviceId: 'x')),
    ]);
    containers.add(offline);
    offline.read(syncServiceProvider).start();
    expect(offline.read(syncServiceProvider).running, isFalse);
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

  test('a like reaches another device with its words; one from an older app (no words) is still a like', () async {
    final server = FakeServer();
    final a = await device(server, 'acct');
    final b = await device(server, 'acct');
    a.read(notebookProvider.notifier).toggleLike('bk', 'c0.b0.s0',
        quote: () => LikedQuote(
            bookId: 'bk', sid: 'c0.b0.s0', bookTitle: 'Walden', author: 'Thoreau', chapterTitle: 'Economy', text: 'Simplify, simplify.', likedAt: DateTime(2026, 11, 20, 8)));
    a.read(notebookProvider.notifier).like('bk', 'c0.b1.s0'); // as an older app sent it: just `true`
    await a.read(syncServiceProvider).syncNow();
    await b.read(syncServiceProvider).syncNow();
    final n = b.read(notebookProvider);
    expect(n.liked, {'bk|c0.b0.s0', 'bk|c0.b1.s0'});
    expect(n.likedNewestFirst.single.text, 'Simplify, simplify.');
    expect(n.likedNewestFirst.single.likedAt, DateTime(2026, 11, 20, 8));

    // Unliked on B: gone from A too, words and all.
    b.read(notebookProvider.notifier).toggleLike('bk', 'c0.b0.s0');
    await b.read(syncServiceProvider).syncNow();
    await a.read(syncServiceProvider).syncNow();
    expect(a.read(notebookProvider).liked, {'bk|c0.b1.s0'});
    expect(a.read(notebookProvider).likedQuotes, isEmpty);
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
      'goal_unit': 'cards',
      'daily_goal_minutes': 10,
      'freezes_per_week': 1,
      'handle': '',
      'pronouns': '',
      'bio': '',
      'avatar': '',
      'genres': <String>[],
      'reading': '',
    });
    await a.read(syncServiceProvider).syncNow();
    expect(server.activity, hasLength(2), reason: 'the outbox is emptied after upload');
  });

  test('a goal in minutes reaches the server as minutes (not as ten cards)', () async {
    final server = FakeServer();
    final a = await device(server, 'dev1');
    a.read(settingsProvider.notifier).update((s) => s.copyWith(goalUnit: GoalUnit.minutes, dailyGoal: 15));
    await a.read(syncServiceProvider).syncNow();
    expect(server.profiles['dev1'], containsPair('goal_unit', 'minutes'));
    expect(server.profiles['dev1'], containsPair('daily_goal_minutes', 15));
  });

  test('reading done before there was a server reaches it: every day, then only the days that change', () async {
    final server = FakeServer();
    final dir = await Directory.systemTemp.createTemp('bookreel_sync');
    dirs.add(dir);
    final store = await JsonStore.open(dir);
    // Fifteen months of reading with no server: nothing is queued for one.
    final before = ProviderContainer(overrides: [
      storeProvider.overrideWithValue(store),
      apiProvider.overrideWithValue(BookReelApi(baseUrl: '', deviceId: 'dev1')),
    ]);
    containers.add(before);
    final habit = before.read(habitProvider.notifier);
    for (var d = 0; d < 450; d++) {
      habit.clock = () => DateTime(2025, 8, 1 + d, 9);
      habit.recordCard(words: 120, dwellMs: 30000, bookId: 'bk', cardRef: 'bk:c$d');
    }
    habit.bookFinished();
    before.read(notebookProvider.notifier).addWord(word: 'quaint', meaning: 'attractively odd', sentence: 'A quaint old house.', bookTitle: 'Emma');

    // The server arrives: the whole history goes up, 400 days at a time.
    final after = ProviderContainer(overrides: [
      storeProvider.overrideWithValue(store),
      apiProvider.overrideWithValue(BookReelApi(baseUrl: 'http://fake', deviceId: 'dev1', httpClient: server.client)),
    ]);
    containers.add(after);
    after.read(habitProvider.notifier).clock = () => DateTime(2026, 10, 25, 20);
    await after.read(syncServiceProvider).syncNow();
    final days = server.statDays['dev1']!;
    expect(days, hasLength(450));
    expect(server.statCalls.map((c) => c.length), [400, 50]);
    expect(days['2025-08-01'], containsPair('cards', 1));
    expect(days['2025-08-01'], containsPair('words', 120));
    expect(days['2026-10-24'], containsPair('cards', 1), reason: 'the last day read');
    expect(server.statTotals['dev1'], {
      'books_finished': 1,
      'streak': isA<int>(),
      'best_streak': isA<int>(),
      'as_of': '2026-10-25',
      'weekly': false,
      'wpm': isA<int>(),
      'words_learned': 1,
    });
    expect(server.activity, isEmpty, reason: 'no raw events from before: the days carry the reading');

    // Nothing new: nothing sent.
    await after.read(syncServiceProvider).syncNow();
    expect(server.statCalls, hasLength(2));

    // A new day's reading: that day alone.
    final online = after.read(habitProvider.notifier);
    online.clock = () => DateTime(2026, 10, 25, 21);
    online.recordCard(words: 120, dwellMs: 30000, bookId: 'bk', cardRef: 'bk:new');
    await after.read(syncServiceProvider).syncNow();
    expect(server.statCalls.last, ['2026-10-25']);
    expect(server.activity, hasLength(1), reason: 'and its verified event, for leagues');
    await store.flush();
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
