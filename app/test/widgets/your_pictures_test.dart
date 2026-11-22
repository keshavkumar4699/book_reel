import 'dart:io';
import 'dart:typed_data';

import 'package:book_reel/core/segmentation/rule_segmenter.dart';
import 'package:book_reel/data/json_store.dart';
import 'package:book_reel/data/library.dart';
import 'package:book_reel/data/settings_provider.dart';
import 'package:book_reel/data/store_provider.dart';
import 'package:book_reel/data/user_pictures.dart';
import 'package:book_reel/features/reader/add_pictures.dart';
import 'package:book_reel/features/reader/reader_screen.dart';
import 'package:book_reel/ui/backdrops.dart';
import 'package:book_reel/ui/kit.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../data/user_pictures_test.dart' show pngOf;
import '../silent_music.dart';

/// A picture picked on the phone.
final class _Picked extends PlatformFile {
  _Picked(this.name, this.bytes);

  @override
  final String name;
  final Uint8List bytes;

  @override
  Uri get uri => Uri.parse('content://picked/$name');
  @override
  get xFile => throw UnimplementedError();
  @override
  int? lengthSync() => bytes.length;
  @override
  Future<int?> length() async => bytes.length;
  @override
  Future<Uint8List> readAsBytes() async => bytes;
  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(bytes);
}

/// Pictures from your phone, added from the row of pictures at the top of
/// the reader: shown at once, kept, and removed with a long press.
void main() {
  final dirs = <Directory>[];
  late Directory pictures;
  late List<PlatformFile> toPick;
  setUp(() {
    quietReader();
    pictures = Directory.systemTemp.createTempSync('your_pictures');
    dirs.add(pictures);
    UserPictures.root = () async => pictures;
    toPick = [];
    pickPictures = () async => toPick;
  });
  tearDownAll(() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final d in dirs) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
  });

  Future<ProviderContainer> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('your_pictures_store');
    dirs.add(dir);
    late ProviderContainer c;
    late String bookId;
    await tester.runAsync(() async {
      c = ProviderContainer(overrides: [storeProvider.overrideWithValue(await JsonStore.open(dir))]);
      c.read(settingsProvider.notifier).update((s) => s.copyWith(
          onboardingDone: true, goalSetupDone: true, gestureTutorialSeen: true, animatedBackground: false, cardLength: CardLength.standard));
      bookId = (await c.read(libraryProvider.notifier).ensureStarterBook())!.id;
    });
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(theme: buildAppTheme(Kit.appLight), home: ReaderScreen(bookId: bookId)),
    ));
    for (var i = 0; i < 25 && find.byType(PageView).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
    }
    await tester.pump();
    return c;
  }

  Future<void> until(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 60 && !done(); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(done(), isTrue);
  }

  Future<void> showControls(WidgetTester tester, ProviderContainer c) async {
    if (c.read(readerChromeProvider)) return; // a tap would hide them
    await tester.tapAt(const Offset(30, 420));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('add a picture from the phone: it’s on screen at once, in the row, and kept', (tester) async {
    final c = await open(tester);
    Backdrop now() => Kit.of(tester.element(find.byType(PageView))).backdrop!;
    final png = await tester.runAsync(() => pngOf(const Color(0xFF101418)));
    toPick = [_Picked('beach_day.png', png!)];
    await showControls(tester, c);
    await tester.tap(find.bySemanticsLabel('Add pictures'));
    await until(tester, () => now().isYours);
    final added = (await tester.runAsync(UserPictures.list))!;
    expect(added, hasLength(1));
    expect(now(), Backdrop.file(added.single));
    expect(c.read(settingsProvider).lastBackdrop, now().id);
    expect(Kit.of(tester.element(find.byType(PageView))).dark, isTrue, reason: 'measured: light text on a dark picture');
    expect(find.bySemanticsLabel('Background: Beach day'), findsOneWidget);

    // A long press on it removes it (from the app, not the phone).
    await showControls(tester, c);
    await tester.longPress(find.bySemanticsLabel('Background: Beach day'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Remove this picture?'), findsOneWidget);
    await tester.tap(find.text('Remove'));
    await until(tester, () => !now().isYours);
    expect(await tester.runAsync(UserPictures.list), isEmpty);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('a file that won’t open as a picture says so, and nothing changes', (tester) async {
    final c = await open(tester);
    final before = Kit.of(tester.element(find.byType(PageView))).backdrop;
    toPick = [_Picked('notes.png', Uint8List.fromList(List.filled(80, 3)))];
    await showControls(tester, c);
    await tester.tap(find.bySemanticsLabel('Add pictures'));
    await until(tester, () => find.text('Those pictures couldn’t be opened').evaluate().isNotEmpty);
    expect(Kit.of(tester.element(find.byType(PageView))).backdrop, before);
    expect(await tester.runAsync(UserPictures.list), isEmpty);
    await tester.pump(const Duration(seconds: 4));
  });
}
