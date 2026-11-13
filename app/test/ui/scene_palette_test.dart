import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:book_reel/data/settings.dart';
import 'package:book_reel/ui/theme.dart';
import 'package:book_reel/ui/vibes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG relative luminance of an sRGB pixel.
double _lum(int r, int g, int b) {
  double lin(int c) {
    final s = c / 255.0;
    return s <= 0.04045 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b);
}

double _contrast(double a, double b) => (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);

/// Where body text sits: reels are centred and hold a limited amount of text
/// (feed_builder.dart `reelWordBudget`), so even the densest stays within the
/// middle 60 % of the screen. Everything else is margins and controls.
const _textTop = 0.2, _textBottom = 0.8;

/// Renders [vibe] with its palette's shade and returns pixel luminances for
/// the text zone and for the rest of the screen (margins, top bar, book row).
Future<({List<double> text, List<double> chrome})> _render(WidgetTester tester, Vibe vibe, Size size, double t) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  ScenePainter(vibe, () => t).paint(canvas, size);
  canvas.drawRect(Offset.zero & size, Paint()..shader = scenePalettes[vibe]!.scrim.createShader(Offset.zero & size));
  final image = await tester.runAsync(() => rec.endRecording().toImage(size.width.toInt(), size.height.toInt()));
  final data = await tester.runAsync(() => image!.toByteData(format: ui.ImageByteFormat.rawRgba));
  image!.dispose();
  final bytes = data!.buffer.asUint8List();
  final text = <double>[], chrome = <double>[];
  final w = size.width.toInt();
  for (var y = 0; y < size.height; y += 3) {
    final f = y / size.height;
    for (var x = (size.width * 0.05).toInt(); x < size.width * 0.95; x += 3) {
      final i = (y * w + x) * 4;
      final l = _lum(bytes[i], bytes[i + 1], bytes[i + 2]);
      (f >= _textTop && f < _textBottom ? text : chrome).add(l);
    }
  }
  return (text: text..sort(), chrome: chrome..sort());
}

void main() {
  for (final vibe in scenePalettes.keys) {
    testWidgets('${vibe.name}: text colours keep their contrast on the scene', (tester) async {
      final p = scenePalettes[vibe]!;
      final ink = p.ink.computeLuminance();
      for (final size in const [Size(412, 915), Size(360, 760)]) {
        for (final t in const [0.0, 61.0, 143.0]) {
          final px = await _render(tester, vibe, size, t);
          // Worst pixels: the brightest under light ink, the darkest under dark ink.
          double worst(List<double> l, double q) => p.lightInk ? l[(q * (l.length - 1)).round()] : l[((1 - q) * (l.length - 1)).round()];
          final where = '${vibe.name} ${size.width.toInt()}x${size.height.toInt()} t=$t';
          double c(Color colour, List<double> px, double q) => _contrast(colour.computeLuminance(), worst(px, q));
          // Where body text sits: AAA for the text, AA for its accents.
          expect(_contrast(ink, worst(px.text, 0.97)), greaterThanOrEqualTo(7.0), reason: '$where body text (AAA)');
          expect(_contrast(ink, worst(px.text, 0.99)), greaterThanOrEqualTo(4.5), reason: '$where body text on highlights');
          expect(c(p.emphasis, px.text, 0.97), greaterThanOrEqualTo(4.5), reason: '$where emphasis');
          expect(c(p.spot, px.text, 0.97), greaterThanOrEqualTo(7.0), reason: '$where spotlight');
          expect(c(p.accent, px.text, 0.97), greaterThanOrEqualTo(4.5), reason: '$where accent');
          // Margins, top bar, book row and action rail: AA.
          expect(_contrast(ink, worst(px.chrome, 0.97)), greaterThanOrEqualTo(4.5), reason: '$where margins and controls');
        }
      }
    });
  }

  test('ink is never pure white or pure black', () {
    for (final p in scenePalettes.values) {
      expect(p.ink, isNot(const Color(0xFFFFFFFF)));
      expect(p.ink, isNot(const Color(0xFF000000)));
      expect(p.shade.length, 11);
    }
  });

  test('highlights: tints of the surface with text in the opposite shade, always readable', () {
    double ratio(Color a, Color b) {
      final la = a.computeLuminance(), lb = b.computeLuminance();
      return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
    }

    final themes = <String, ReadingTheme>{
      for (final v in Vibe.values)
        if (v != Vibe.paper) v.name: readingThemeForVibe(v, ReadingTheme.of(ReadingThemeId.paper)),
      for (final id in ReadingThemeId.values) 'paper/${id.name}': ReadingTheme.of(id),
    };
    for (final MapEntry(key: name, value: t) in themes.entries) {
      expect(t.highlights, hasLength(4));
      for (final fill in t.highlights) {
        expect(fill.a, 1, reason: '$name: opaque fills');
        expect(ratio(t.highlightInk, fill), greaterThanOrEqualTo(4.5), reason: '$name: text on $fill');
      }
      // Light fills on dark surfaces, deep fills on light ones.
      final light = t.highlights.every((f) => f.computeLuminance() > 0.3);
      expect(light, t.isDark, reason: name);
    }
  });
}
