import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:book_reel/features/profile/avatar_cropper.dart';
import 'package:book_reel/ui/kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A wide picture: red on the left, blue on the right.
Future<Uint8List> _photo() async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.drawRect(const Rect.fromLTWH(0, 0, 150, 200), Paint()..color = const Color(0xFFFF0000));
  c.drawRect(const Rect.fromLTWH(150, 0, 150, 200), Paint()..color = const Color(0xFF0000FF));
  final image = await rec.endRecording().toImage(300, 200);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return png!.buffer.asUint8List();
}

void main() {
  Future<Uint8List?> crop(WidgetTester tester, {required bool use}) async {
    final photo = (await tester.runAsync(_photo))!;
    Uint8List? result;
    var done = false;
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(Kit.appLight),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await showAvatarCropper(context, photo);
            done = true;
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // Let the picture decode.
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await tester.pump();
    }
    expect(find.text('Move and scale'), findsOneWidget);
    await tester.tap(find.text(use ? 'Use photo' : 'Cancel'));
    for (var i = 0; i < 10 && !done; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(done, isTrue);
    return result;
  }

  testWidgets('"Use photo" gives a 512 px square that fills the circle', (tester) async {
    final png = await crop(tester, use: true);
    expect(png, isNotNull);
    final size = await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(png!);
      final frame = await codec.getNextFrame();
      final s = (frame.image.width, frame.image.height);
      frame.image.dispose();
      return s;
    });
    expect(size, (512, 512));
  });

  testWidgets('Cancel keeps the old picture', (tester) async {
    expect(await crop(tester, use: false), isNull);
  });
}
