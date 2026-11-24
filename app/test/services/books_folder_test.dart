import 'dart:io';
import 'dart:typed_data';

import 'package:book_reel/data/json_store.dart';
import 'package:book_reel/data/library.dart';
import 'package:book_reel/data/store_provider.dart';
import 'package:book_reel/services/books_folder.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fake_books_folder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late JsonStore store;
  late FakeFolderPhone phone;

  ProviderContainer container() {
    final c = ProviderContainer(overrides: [storeProvider.overrideWithValue(store)]);
    addTearDown(c.dispose);
    return c;
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('books_folder');
    store = await JsonStore.open(dir);
    phone = FakeFolderPhone(dir);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(BooksFolderNotifier.channel, phone.handle);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(BooksFolderNotifier.channel, null);
    await store.flush();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  List<String> titles(ProviderContainer c) => [for (final b in c.read(libraryProvider)) b.title]..sort();

  test('a chosen folder’s books arrive once; one removed stays out until its file changes', () async {
    final evening = epubNamed('Evening');
    phone
      ..put('a', 'Morning.epub', epubNamed('Morning'))
      ..put('b', 'Evening.epub', evening)
      ..put('x', 'Broken.epub', Uint8List.fromList(List.filled(64, 7)));
    final c = container();
    final folder = c.read(booksFolderProvider.notifier);

    final added = await folder.choose();
    expect([for (final b in added!) b.title]..sort(), ['Evening', 'Morning']);
    expect(titles(c), ['Evening', 'Morning'], reason: 'a file that isn’t a book is left alone');
    final state = c.read(booksFolderProvider);
    expect((state.chosen, state.name, state.scanning, state.unavailable), (true, 'Books', false, false));
    expect(state.lastAdded..sort(), ['Evening', 'Morning']);
    expect(phone.count('copy'), 3);

    // Looked at again: nothing is read twice, the broken file included.
    expect(await folder.scan(force: true), isEmpty);
    expect(phone.count('copy'), 3);
    // On its own (the app coming back), at most once a minute.
    expect(await folder.scan(), isEmpty);
    expect(phone.count('list'), 2);

    // A new file arrives.
    phone.put('c', 'Night.epub', epubNamed('Night'));
    expect([for (final b in await folder.scan(force: true)) b.title], ['Night']);

    // Removed from the Library: it stays out…
    final morning = c.read(libraryProvider).firstWhere((b) => b.title == 'Morning');
    await c.read(libraryProvider.notifier).remove(morning.id);
    expect(await folder.scan(force: true), isEmpty);
    expect(titles(c), ['Evening', 'Night']);
    // …until a new copy of the file is put there.
    phone.put('a', 'Morning.epub', epubNamed('Morning'), modified: 2);
    expect([for (final b in await folder.scan(force: true)) b.title], ['Morning']);

    // The same book under another name isn't added twice.
    phone.put('d', 'Evening (1).epub', evening);
    expect(await folder.scan(force: true), isEmpty);
    expect(titles(c), ['Evening', 'Morning', 'Night']);
    expect(Directory(dir.path).listSync().where((f) => f.path.endsWith('.book')), isEmpty, reason: 'the copies are deleted');
  });

  test('the folder is remembered: after a restart nothing is read again', () async {
    phone.put('a', 'Morning.epub', epubNamed('Morning'));
    await container().read(booksFolderProvider.notifier).choose();
    final again = container();
    expect(again.read(booksFolderProvider).name, 'Books');
    expect(await again.read(booksFolderProvider.notifier).scan(), isEmpty);
    expect(phone.count('copy'), 1);
  });

  test('a folder that can’t be read any more says so; choosing it again mends it', () async {
    phone.put('a', 'Morning.epub', epubNamed('Morning'));
    final c = container();
    final folder = c.read(booksFolderProvider.notifier);
    await folder.choose();
    phone.readable = false;
    expect(await folder.scan(force: true), isEmpty);
    expect(c.read(booksFolderProvider).unavailable, isTrue);

    phone.readable = true;
    phone.put('b', 'Evening.epub', epubNamed('Evening'));
    expect([for (final b in (await folder.choose())!) b.title], ['Evening'], reason: 'the books already read stay read');
    expect(c.read(booksFolderProvider).unavailable, isFalse);
  });

  test('stopping gives the folder’s access back; the books stay; cancelling the picker changes nothing', () async {
    phone.put('a', 'Morning.epub', epubNamed('Morning'));
    final c = container();
    final folder = c.read(booksFolderProvider.notifier);
    await folder.choose();
    await folder.forget();
    expect(c.read(booksFolderProvider).chosen, isFalse);
    expect(phone.count('release'), 1);
    expect(titles(c), ['Morning']);
    expect(await folder.scan(force: true), isEmpty);

    phone.picks = false;
    expect(await folder.choose(), isNull);
    expect(c.read(booksFolderProvider).chosen, isFalse);
  });

  test('off Android (no folder picker), nothing happens', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(BooksFolderNotifier.channel, null);
    final c = container();
    expect(await c.read(booksFolderProvider.notifier).choose(), isNull);
    expect(c.read(booksFolderProvider).chosen, isFalse);
  });
}
