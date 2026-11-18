import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:book_reel/data/settings.dart';
import 'package:book_reel/ui/backdrops.dart';
import 'package:book_reel/ui/vibes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../silent_music.dart';

/// An image [w] × [h] whose pixel colour comes from [at] (x, y in 0–1).
Uint8List _pixels(int w, int h, (int, int, int) Function(double x, double y) at) {
  final out = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final (r, g, b) = at(x / (w - 1), y / (h - 1));
      final i = (y * w + x) * 4;
      out
        ..[i] = r
        ..[i + 1] = g
        ..[i + 2] = b
        ..[i + 3] = 255;
    }
  }
  return out;
}

double _lum(int r, int g, int b) => luminanceOf(Color.fromARGB(255, r, g, b));

/// Every band keeps its contrast over the brightest (or darkest) tenth of
/// its pixels, unless its shade is already at the cap.
void _expectReadable(Uint8List rgba, int w, int h, ScenePalette p, String what) {
  final ink = luminanceOf(p.ink);
  for (var k = 0; k <= 10; k++) {
    final cols = <(int, int, int)>[];
    for (var y = 0; y < h; y++) {
      if ((y / (h - 1) * 10).round() != k) continue;
      for (var x = 0; x < w; x++) {
        final i = (y * w + x) * 4;
        cols.add((rgba[i], rgba[i + 1], rgba[i + 2]));
      }
    }
    cols.sort((a, b) => _lum(a.$1, a.$2, a.$3).compareTo(_lum(b.$1, b.$2, b.$3)));
    final worst = cols[((cols.length - 1) * (p.lightInk ? 0.9 : 0.1)).round()];
    final a = p.shade[k];
    final t = p.tint;
    final bg = Color.from(
      alpha: 1,
      red: worst.$1 / 255 + (t.r - worst.$1 / 255) * a,
      green: worst.$2 / 255 + (t.g - worst.$2 / 255) * a,
      blue: worst.$3 / 255 + (t.b - worst.$3 / 255) * a,
    );
    final goal = k >= 2 && k <= 8 ? pictureBodyContrast : pictureEdgeContrast;
    if (a >= 0.9) continue; // the cap: shadows do the rest
    expect(contrastRatio(ink, luminanceOf(bg)), greaterThanOrEqualTo(goal - 0.01), reason: '$what band $k (shade $a)');
    expect(contrastRatio(luminanceOf(p.emphasis), luminanceOf(bg)), greaterThanOrEqualTo(pictureEdgeContrast - 0.01),
        reason: '$what emphasis, band $k');
  }
}

void main() {
  test('your pictures replace the painted scenes; names read as words', () {
    expect(backdropsFrom(['assets/images/logo.png', 'assets/images/backgrounds/README.md']).map((b) => b.vibe),
        [...dayScenes, ...nightScenes], reason: 'no pictures yet: the scenes');
    final mine = backdropsFrom([
      'assets/images/backgrounds/lake_at_dawn.jpg',
      'assets/images/backgrounds/City-Night.WEBP',
      'assets/images/backgrounds/notes.txt',
      'assets/images/logo_512.png',
    ]);
    expect(mine.map((b) => b.label), ['City Night', 'Lake at dawn']);
    expect(mine.every((b) => b.isPicture), isTrue);
    expect(Backdrop.paper.label, 'Plain');
    expect(const Backdrop.scene(Vibe.night).label, 'Night');
  });

  test('each book opens on a random picture: never Plain, never the last one again', () {
    final all = backdropsFrom(['assets/images/backgrounds/a.jpg', 'assets/images/backgrounds/b.jpg', 'assets/images/backgrounds/c.jpg']);
    final seen = <String>{};
    final random = math.Random(7);
    for (var i = 0; i < 60; i++) {
      final b = pickBackdrop([...all, Backdrop.paper], lastId: 'assets/images/backgrounds/b.jpg', random: random);
      expect(b.isPaper, isFalse);
      seen.add(b.id);
    }
    expect(seen, {'assets/images/backgrounds/a.jpg', 'assets/images/backgrounds/c.jpg'});
    // Only one picture: it's shown again.
    expect(pickBackdrop([all.first], lastId: all.first.id).id, all.first.id);
    expect(pickBackdrop([...all], random: FirstPick()).id, 'assets/images/backgrounds/a.jpg');
  });

  test('text stays readable on any picture: bright, dark, half and half, busy', () {
    const w = 40, h = 88;
    final cases = {
      'snow (white)': _pixels(w, h, (_, _) => (250, 250, 248)),
      'night (black)': _pixels(w, h, (_, _) => (8, 10, 18)),
      'sky over a dark lake': _pixels(w, h, (x, y) => y < 0.5 ? (170, 205, 245) : (20, 40, 45)),
      'sunset gradient': _pixels(w, h, (x, y) => ((255 * (1 - y)).round(), (140 * (1 - y)).round(), (60 + 80 * y).round())),
      'busy stripes': _pixels(w, h, (x, y) => (x * 9).floor().isEven ? (245, 240, 230) : (30, 25, 20)),
      'mid grey': _pixels(w, h, (_, _) => (128, 128, 128)),
    };
    for (final MapEntry(key: what, value: rgba) in cases.entries) {
      final p = paletteForPixels(rgba, w, h);
      expect(p.shade, hasLength(11));
      _expectReadable(rgba, w, h, p, what);
    }
    expect(paletteForPixels(cases['snow (white)']!, w, h).lightInk, isFalse, reason: 'dark text on a bright picture');
    expect(paletteForPixels(cases['night (black)']!, w, h).lightInk, isTrue, reason: 'light text on a dark picture');
    expect(paletteForPixels(cases['night (black)']!, w, h).shade.every((a) => a < 0.3), isTrue,
        reason: 'a dark picture is barely shaded');
  });

  testWidgets('a picture is measured as the screen shows it: decoded small, cropped to the screen', (tester) async {
    // A landscape picture: bright on the left and right, dark in the middle third.
    final look = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(const Rect.fromLTWH(0, 0, 1800, 1200), Paint()..color = const Color(0xFFF4F1EA));
      canvas.drawRect(const Rect.fromLTWH(600, 0, 600, 1200), Paint()..color = const Color(0xFF101418));
      final image = await recorder.endRecording().toImage(1800, 1200);
      final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      return lookForPicture(_Bundle(png), 'assets/images/backgrounds/x.png', 0.46);
    });
    expect(look!.size, const Size(1800, 1200));
    expect(look.palette.lightInk, isTrue, reason: 'a phone shows the dark middle of this picture');
    // Covering a 1080 × 2340 screen: decoded at 3510 × 2340, not larger than the picture itself.
    final sized = sizedForScreen(const AssetImage('x'), look.size, const Size(1080, 2340));
    expect(sized, isA<AssetImage>(), reason: 'smaller than the screen needs: as it is');
    final big = sizedForScreen(const AssetImage('x'), const Size(6000, 4000), const Size(1080, 2340)) as ResizeImage;
    expect((big.width, big.height), (3510, 2340));
  });
}

class _Bundle extends CachingAssetBundle {
  _Bundle(this.data);
  final ByteData data;
  @override
  Future<ByteData> load(String key) async => data;
}
