import 'dart:io';
import 'dart:ui' as ui;

import 'package:book_reel/data/user_pictures.dart';
import 'package:book_reel/ui/backdrops.dart';
import 'package:book_reel/ui/vibes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A small PNG, [w] × [h], of one colour.
Future<Uint8List> pngOf(Color colour, {int w = 60, int h = 90}) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..color = colour);
  final image = await recorder.endRecording().toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('pictures');
    UserPictures.root = () async => dir;
  });
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('pictures you add are kept by the app, newest first, under their own names', () async {
    final dark = await pngOf(const Color(0xFF101418)), light = await pngOf(const Color(0xFFF4F1EA));
    final first = await UserPictures.add([(name: 'beach_day.png', bytes: light)]);
    final second = await UserPictures.add([(name: 'night-sky.png', bytes: dark), (name: 'IMG 2041.PNG', bytes: light)]);
    expect(first, hasLength(1));
    expect(second, hasLength(2));
    final all = await UserPictures.list();
    expect(all, [...second, ...first], reason: 'the newest first; each batch in the order picked');
    expect(all.map(UserPictures.labelOf), ['Night sky', 'IMG 2041', 'Beach day']);
    expect(File(first.single).readAsBytesSync(), light, reason: 'a copy: the original can go');
    expect(all.every((p) => p.startsWith('${dir.path}/backgrounds/')), isTrue);

    await UserPictures.remove(second.first);
    expect(await UserPictures.list(), [second.last, first.single]);
  });

  test('a file that isn’t a picture is left out', () async {
    final good = await pngOf(const Color(0xFF336699));
    final added = await UserPictures.add([
      (name: 'notes.png', bytes: Uint8List.fromList(List.filled(64, 7))),
      (name: 'lake.png', bytes: good),
    ]);
    expect(added.map(UserPictures.labelOf), ['Lake']);
    expect(await UserPictures.opens(Uint8List(0)), isFalse);
  });

  test('your pictures come before the app’s (after the study scenes), measured like the app’s own', () async {
    final added = await UserPictures.add([(name: 'reading_nook.png', bytes: await pngOf(const Color(0xFFF4F1EA)))]);
    final all = backdropsFrom(const ['assets/images/day_dreamy.jpg'], yours: added);
    expect(all.take(studyScenes.length).map((b) => b.vibe), studyScenes);
    final yours = all[studyScenes.length];
    expect(yours, Backdrop.file(added.single));
    expect(yours.isYours, isTrue);
    expect(yours.label, 'Reading nook');
    expect(yours.id, 'file:${added.single.split('/').last}', reason: 'kept by name: storage can move between updates');
    expect(yours.image, isA<FileImage>());
    expect(all.last, const Backdrop.picture('assets/images/day_dreamy.jpg'));
    // With only your pictures, the painted scenes step aside as they do for the app's.
    expect(backdropsFrom(const [], yours: added).where((b) => !studyScenes.contains(b.vibe)), [Backdrop.file(added.single)]);
    // Measured from the file: a bright picture gets dark text.
    final look = await lookForPicture(_NoBundle(), yours.source!, 0.45);
    expect(look.palette.lightInk, isFalse);
    expect(look.size, const Size(60, 90));
  });
}

class _NoBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) => throw StateError('not an asset: $key');
}
