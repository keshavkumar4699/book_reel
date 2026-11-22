import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:book_reel/ui/backdrops.dart';
import 'package:book_reel/ui/vibes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Text on every picture in the app's folders and every painted scene, as a
/// phone shows it: the picture covering the screen, the shade on top, then
/// each colour of text over every pixel, band by band from top to bottom.
/// In each band, 90 % of the pixels keep body text at 7:1 in the middle of
/// the screen (4.5:1 at the edges), and softer text (the chapter, a track's
/// artist, labels) and emphasis at 4.5:1. (The last 10 % are small bright
/// or dark specks; the text's shadow covers those.)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final pictures = [
    for (final dir in pictureDirs)
      if (Directory(dir).existsSync())
        for (final f in Directory(dir).listSync().whereType<File>())
          if (RegExp(r'\.(jpe?g|png|webp)$', caseSensitive: false).hasMatch(f.path) && !f.path.split('/').last.startsWith('logo'))
            f.path.replaceAll('\\', '/'),
  ]..sort();

  test('the app has pictures to check', () => expect(pictures, isNotEmpty));

  for (final asset in pictures) {
    for (final aspect in const [0.45, 0.5625]) {
      test('${asset.split('/').last} on a ${aspect == 0.45 ? 'tall' : 'wide'} phone: every colour of text keeps its contrast', () async {
        final look = await lookForPicture(_Disk(), asset, aspect);
        final shown = await _shown(File(asset).readAsBytesSync(), aspect);
        _expectLegible(shown, look.palette, '${asset.split('/').last} @$aspect');
      });
    }
  }

  for (final vibe in scenePalettes.keys) {
    testWidgets('the ${vibe.name} scene: every colour of text keeps its contrast, as it moves', (tester) async {
      for (final t in const [0.0, 61.0, 143.0]) {
        const size = Size(360, 800);
        final rec = ui.PictureRecorder();
        ScenePainter(vibe, () => t).paint(Canvas(rec), size);
        final image = await tester.runAsync(() => rec.endRecording().toImage(360, 800));
        final data = await tester.runAsync(() => image!.toByteData(format: ui.ImageByteFormat.rawRgba));
        image!.dispose();
        _expectLegible((data!.buffer.asUint8List(), 360, 800), scenePalettes[vibe]!, '${vibe.name} t=$t');
      }
    });
  }
}

class _Disk extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(File(key).readAsBytesSync());
}

/// The picture as a 360-wide phone of [aspect] shows it: covering the
/// screen, centred.
Future<(Uint8List, int, int)> _shown(Uint8List encoded, double aspect) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(encoded);
  final descriptor = await ui.ImageDescriptor.encoded(buffer);
  final w0 = descriptor.width, h0 = descriptor.height;
  // Decoded so the cropped part is about 360 wide.
  final cover = w0 / h0 > aspect ? (h0 * aspect) / w0 : 1.0;
  final codec = await descriptor.instantiateCodec(targetWidth: math.min(w0, (360 / cover).round()));
  final image = (await codec.getNextFrame()).image;
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final w = image.width, h = image.height;
  image.dispose();
  var cw = w, ch = h, cx = 0, cy = 0;
  if (w / h > aspect) {
    cw = math.max(1, (h * aspect).round());
    cx = (w - cw) ~/ 2;
  } else {
    ch = math.max(1, (w / aspect).round());
    cy = (h - ch) ~/ 2;
  }
  final src = data.buffer.asUint8List();
  final out = Uint8List(cw * ch * 4);
  for (var y = 0; y < ch; y++) {
    out.setRange(y * cw * 4, (y + 1) * cw * 4, src, ((y + cy) * w + cx) * 4);
  }
  return (out, cw, ch);
}

double _lin(double c) => c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
double _lum(double r, double g, double b) => 0.2126 * _lin(r) + 0.7152 * _lin(g) + 0.0722 * _lin(b);

/// [shown] with [p]'s shade over it, checked band by band.
void _expectLegible((Uint8List, int, int) shown, ScenePalette p, String what) {
  final (rgba, w, h) = shown;
  final ink = p.ink, emphasisLum = luminanceOf(p.emphasis), inkLum = luminanceOf(ink);
  final soft = p.lightInk ? lightSoftText : darkSoftText;
  final bands = List.generate(11, (_) => (ink: <double>[], soft: <double>[], emphasis: <double>[]));
  for (var y = 0; y < h; y++) {
    final f = y / (h - 1) * 10;
    final k = f.round();
    // The shade between two stops is a blend of both.
    final i0 = f.floor().clamp(0, 10), i1 = f.ceil().clamp(0, 10);
    final a = p.shade[i0] + (p.shade[i1] - p.shade[i0]) * (f - i0);
    for (var x = 0; x < w; x += 2) {
      final i = (y * w + x) * 4;
      final r = rgba[i] / 255 + (p.tint.r - rgba[i] / 255) * a;
      final g = rgba[i + 1] / 255 + (p.tint.g - rgba[i + 1] / 255) * a;
      final b = rgba[i + 2] / 255 + (p.tint.b - rgba[i + 2] / 255) * a;
      final bg = _lum(r, g, b);
      final softLum = _lum(r + (ink.r - r) * soft, g + (ink.g - g) * soft, b + (ink.b - b) * soft);
      bands[k].ink.add(contrastRatio(inkLum, bg));
      bands[k].soft.add(contrastRatio(softLum, bg));
      bands[k].emphasis.add(contrastRatio(emphasisLum, bg));
    }
  }
  double tenth(List<double> l) => (l..sort())[((l.length - 1) * 0.1).round()];
  for (var k = 0; k <= 10; k++) {
    if (p.shade[k] >= 0.9) continue; // the most shade there is: shadows do the rest
    final body = k >= 2 && k <= 8;
    expect(tenth(bands[k].ink), greaterThanOrEqualTo(body ? 6.9 : 4.5), reason: '$what: body text, band $k');
    expect(tenth(bands[k].soft), greaterThanOrEqualTo(4.45), reason: '$what: softer text, band $k');
    expect(tenth(bands[k].emphasis), greaterThanOrEqualTo(4.45), reason: '$what: emphasis, band $k');
  }
}
