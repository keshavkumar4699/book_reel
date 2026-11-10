import 'dart:io';
import 'dart:ui' show Color;

import 'package:book_reel/data/api_client.dart';
import 'package:book_reel/data/book_voice.dart';
import 'package:book_reel/data/json_store.dart';
import 'package:book_reel/data/library.dart';
import 'package:book_reel/data/settings.dart';
import 'package:book_reel/data/settings_provider.dart';
import 'package:book_reel/data/store_provider.dart';
import 'package:book_reel/ui/typography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late JsonStore store;
  late FakeServer server;

  ProviderContainer container() => ProviderContainer(overrides: [
        storeProvider.overrideWithValue(store),
        apiProvider.overrideWithValue(BookReelApi(baseUrl: 'http://fake', deviceId: 'd1', httpClient: server.client)),
      ]);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('bookvoice');
    store = await JsonStore.open(dir);
    server = FakeServer();
  });

  tearDown(() async {
    await store.flush();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('a book gets its voice on import; the free tier never asks the server', () async {
    final c = container();
    final meta = (await c.read(libraryProvider.notifier).ensureStarterBook())!;
    expect(BookVoice.values.map((v) => v.name), contains(meta.voice));
    expect(meta.voiceSource, 'rules');
    final book = await c.read(bookContentProvider(meta.id).future);
    await c.read(bookVoiceProvider).ensure(meta.id, book);
    expect(server.profileRequests, isEmpty);
    expect(c.read(libraryProvider).single.voiceSource, 'rules');
    c.dispose();
  });

  test('paid tiers ask the AI once per book and keep its choice across restarts', () async {
    var c = container();
    c.read(settingsProvider.notifier).update((s) => s.copyWith(tier: Tier.plus));
    final meta = (await c.read(libraryProvider.notifier).ensureStarterBook())!;
    final book = await c.read(bookContentProvider(meta.id).future);
    server.profileVoice = 'fantasy';
    await c.read(bookVoiceProvider).ensure(meta.id, book);
    await c.read(bookVoiceProvider).ensure(meta.id, book);
    expect(server.profileRequests, hasLength(1));
    final sent = server.profileRequests.single;
    expect(sent['tier'], 'plus');
    expect((sent['book'] as Map)['title'], "Alice's Adventures in Wonderland");
    expect((sent['book'] as Map)['content_hash'], meta.id);
    // Only a short opening sample leaves the device, never the whole book.
    expect((sent['sample'] as String).length, inInclusiveRange(500, 6000));
    expect(c.read(libraryProvider).single.voice, 'fantasy');
    expect(c.read(libraryProvider).single.voiceSource, 'ai');
    c.dispose();
    await store.flush();

    c = container();
    c.read(settingsProvider.notifier).update((s) => s.copyWith(tier: Tier.plus));
    expect(c.read(libraryProvider).single.voice, 'fantasy');
    await c.read(bookVoiceProvider).ensure(meta.id, book);
    expect(server.profileRequests, hasLength(1), reason: 'the AI choice is stored with the book');
    c.dispose();
  });

  test('server errors and unknown voices keep the on-device choice', () async {
    final c = container();
    c.read(settingsProvider.notifier).update((s) => s.copyWith(tier: Tier.pro));
    final meta = (await c.read(libraryProvider.notifier).ensureStarterBook())!;
    final book = await c.read(bookContentProvider(meta.id).future);
    server.profileVoice = null; // 500
    await c.read(bookVoiceProvider).ensure(meta.id, book);
    expect(c.read(libraryProvider).single.voice, meta.voice);
    expect(c.read(libraryProvider).single.voiceSource, 'rules');

    final c2 = container();
    c2.read(settingsProvider.notifier).update((s) => s.copyWith(tier: Tier.pro));
    server.profileVoice = 'comic-sans';
    await c2.read(bookVoiceProvider).ensure(meta.id, book);
    expect(c2.read(libraryProvider).single.voice, meta.voice);
    expect(c2.read(libraryProvider).single.voiceSource, 'rules');
    c.dispose();
    c2.dispose();
  });

  test("settings: readers on an old default font move to the book's own fonts; chosen fonts stay", () {
    ReadingFont font(Map<String, dynamic> saved) => AppSettings.fromJson(saved).font;
    expect(const AppSettings().font, ReadingFont.book);
    expect(font({}), ReadingFont.book, reason: 'v1 with nothing saved');
    expect(font({'font': 'literata'}), ReadingFont.book, reason: 'v1 default');
    expect(font({'layoutVersion': 2, 'font': 'atkinson'}), ReadingFont.book, reason: 'v2 default');
    expect(font({'layoutVersion': 2, 'font': 'literata'}), ReadingFont.literata, reason: 'picked on purpose in v2');
    expect(font({'layoutVersion': 2, 'font': 'system'}), ReadingFont.system);
    expect(font({'font': 'atkinson'}), ReadingFont.atkinson, reason: 'picked on purpose in v1');
    expect(font({'layoutVersion': 3, 'font': 'atkinson'}), ReadingFont.atkinson, reason: 'picked after the new default');
    // Saving stamps the current version, so the migration runs once.
    final saved = AppSettings.fromJson({'layoutVersion': 2, 'font': 'atkinson'}).toJson();
    expect(saved['layoutVersion'], currentLayoutVersion);
    expect(AppSettings.fromJson({...saved, 'font': 'atkinson'}).font, ReadingFont.atkinson);
  });

  test('fonts resolve per book, unless the reader chose one font for everything', () {
    const own = AppSettings();
    final fantasy = BookType(BookVoice.fantasy, own);
    expect(fantasy.bodyFamily, 'Alegreya');
    expect(fantasy.displayFamily, 'Cinzel');
    final scifi = BookType(BookVoice.scifi, own);
    expect(scifi.body(color: const Color(0xFF000000)).fontFamily, 'Exo2');
    expect(scifi.display(color: const Color(0xFF000000), size: 30).fontFamily, 'Orbitron');
    // Every voice has a distinct body/display pair.
    expect({for (final v in voiceStyles.values) '${v.body}|${v.display}'}, hasLength(BookVoice.values.length));

    final hyperlegible = BookType(BookVoice.fantasy, own.copyWith(font: ReadingFont.atkinson));
    expect(hyperlegible.bodyFamily, 'AtkinsonHyperlegible');
    expect(hyperlegible.displayFamily, 'AtkinsonHyperlegible');
    // The reader's size always applies (voices only compensate for x-height).
    final big = BookType(BookVoice.classic, own.copyWith(fontSize: 28));
    expect(big.body(color: const Color(0xFF000000)).fontSize, 28);
  });
}
