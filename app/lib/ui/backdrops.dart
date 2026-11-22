import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_assets.dart';
import '../data/settings.dart';
import 'kit.dart';
import 'vibes.dart';
import '../l10n/l10n.dart';

/// Background pictures (JPG, PNG or WebP) are every picture in these folders
/// (both listed in pubspec.yaml), the app's logo files excepted. A picture
/// added to either is in the next build; until there are any, the painted
/// scenes are used.
const pictureDirs = ['assets/images/', 'assets/images/backgrounds/'];
const backgroundsDir = 'assets/images/backgrounds/';

final _pictureFile = RegExp(r'\.(jpe?g|png|webp)$', caseSensitive: false);

/// The pictures among [assets], by file name.
List<String> picturesIn(Iterable<String> assets) => [
      for (final a in assets)
        if (_pictureFile.hasMatch(a) && pictureDirs.contains(a.substring(0, a.lastIndexOf('/') + 1)) && !_isLogo(a)) a,
    ]..sort((a, b) => a.split('/').last.toLowerCase().compareTo(b.split('/').last.toLowerCase()));

bool _isLogo(String asset) => asset.split('/').last.toLowerCase().startsWith('logo');

/// What the reels sit on: one of your own pictures, a painted scene (until
/// you add pictures), or Paper, the plain page.
@immutable
class Backdrop {
  const Backdrop.picture(String this.asset) : vibe = null;
  const Backdrop.scene(Vibe this.vibe) : asset = null;

  /// The plain page (follows the reading theme: paper, sepia, dark…).
  static const paper = Backdrop.scene(Vibe.paper);

  final String? asset;
  final Vibe? vibe;

  bool get isPicture => asset != null;
  bool get isPaper => vibe == Vibe.paper;

  /// Kept as the last one shown, so the next book opens on another.
  String get id => asset ?? 'scene:${vibe!.name}';

  /// The picture's file name as words ("lake_at_dawn.jpg" → "Lake at dawn"),
  /// or the scene's name.
  String get label {
    final a = asset;
    if (a == null) return isPaper ? tr('Plain') : tr(vibeStyles[vibe]!.label);
    final name = a.split('/').last.replaceFirst(_pictureFile, '').replaceAll(RegExp(r'[_\-]+'), ' ').trim();
    return name.isEmpty ? tr('Picture') : name[0].toUpperCase() + name.substring(1);
  }

  @override
  bool operator ==(Object other) => other is Backdrop && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Backdrop($id)';
}

/// Your pictures, or until there are any the painted scenes (day, then night).
List<Backdrop> backdropsFrom(Iterable<String> assets) {
  final pictures = picturesIn(assets);
  return pictures.isNotEmpty
      ? [for (final p in pictures) Backdrop.picture(p)]
      : [for (final v in [...dayScenes, ...nightScenes]) Backdrop.scene(v)];
}

final backdropsProvider = FutureProvider<List<Backdrop>>((ref) async => backdropsFrom(await AppAssets.list()));

/// Picks each book's first picture (tests make it predictable).
math.Random backdropRandom = math.Random();

/// A random one of [all] for a book just opened: never Paper, and never the
/// one shown last ([lastId]) when there's a choice.
Backdrop pickBackdrop(List<Backdrop> all, {String? lastId, math.Random? random}) {
  final fresh = [for (final b in all) if (!b.isPaper && b.id != lastId) b];
  final pool = fresh.isNotEmpty ? fresh : [for (final b in all) if (!b.isPaper) b];
  if (pool.isEmpty) return Backdrop.paper;
  return pool[(random ?? math.Random()).nextInt(pool.length)];
}

// ---------------------------------------------------------------- colours

/// A picture's look on screen: the text colours that suit it, and its size
/// (so it's decoded no larger than the screen needs).
@immutable
class PictureLook {
  const PictureLook(this.palette, this.size);
  final ScenePalette palette;
  final Size size;
}

/// Text over a picture keeps 7:1 contrast (WCAG AAA) where body text sits,
/// the middle 60 % of the screen, and 4.5:1 (AA) everywhere else.
const pictureBodyContrast = 7.0;
const pictureEdgeContrast = 4.5;

/// Ink for light text (a warm off-white: pure white blooms on photos) and
/// for dark text.
const lightPictureInk = Color(0xFFF6F2EA);
const darkPictureInk = Color(0xFF1C1A17);

typedef _Rgb = (double, double, double);

double _lin(double c) => c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
double _lum(_Rgb c) => 0.2126 * _lin(c.$1) + 0.7152 * _lin(c.$2) + 0.0722 * _lin(c.$3);
_Rgb _rgbOf(Color c) => (c.r, c.g, c.b);
_Rgb _mix(_Rgb a, _Rgb b, double t) => (a.$1 + (b.$1 - a.$1) * t, a.$2 + (b.$2 - a.$2) * t, a.$3 + (b.$3 - a.$3) * t);
Color _colorOf(_Rgb c) => Color.from(alpha: 1, red: c.$1.clamp(0, 1), green: c.$2.clamp(0, 1), blue: c.$3.clamp(0, 1));

/// WCAG contrast ratio of two relative luminances.
double contrastRatio(double a, double b) => (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);

/// Relative luminance of [c] (WCAG).
double luminanceOf(Color c) => _lum(_rgbOf(c));

/// The shade the text needs over each part of the screen: a picture shown
/// as [rgba] ([width] × [height], already cropped to what the screen shows)
/// is measured in 11 bands from top to bottom, where the shade's stops are.
/// Light ink goes on a shade of the picture's own darkest hue, dark ink on
/// a light veil, whichever leaves more of the picture to see; each band is
/// shaded just enough for the text to keep its contrast over the brightest
/// (or darkest) tenth of that band. Text shadows cover the rest.
ScenePalette paletteForPixels(Uint8List rgba, int width, int height) {
  const stops = 11;
  final bands = List.generate(stops, (_) => <(_Rgb, double)>[]);
  var r = 0.0, g = 0.0, b = 0.0;
  for (var y = 0; y < height; y++) {
    final band = (y / math.max(1, height - 1) * (stops - 1)).round();
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      final c = (rgba[i] / 255, rgba[i + 1] / 255, rgba[i + 2] / 255);
      bands[band].add((c, _lum(c)));
      r += c.$1;
      g += c.$2;
      b += c.$3;
    }
  }
  final n = math.max(1, width * height);
  final average = HSLColor.fromColor(_colorOf((r / n, g / n, b / n)));
  final hue = average.hue;
  final saturation = average.saturation;
  // Tenth-brightest and tenth-darkest pixel of each band (the band's own neighbours if empty).
  _Rgb percentile(List<(_Rgb, double)> px, double p) {
    final sorted = [...px]..sort((a, b) => a.$2.compareTo(b.$2));
    return sorted[((sorted.length - 1) * p).round()].$1;
  }

  final filled = [for (var k = 0; k < stops; k++) bands[k].isNotEmpty ? bands[k] : bands.firstWhere((x) => x.isNotEmpty, orElse: () => [((0.5, 0.5, 0.5), 0.21)])];
  final bright = [for (final px in filled) percentile(px, 0.9)];
  final dark = [for (final px in filled) percentile(px, 0.1)];
  double target(int k) => k >= 2 && k <= 8 ? pictureBodyContrast : pictureEdgeContrast;

  // The least shade (between [min] and 0.9) that gives [ink] its contrast over [worst].
  double alphaFor(_Rgb worst, _Rgb tint, double inkLum, double goal, {required bool light, required double min}) {
    bool ok(double a) {
      final bg = _lum(_mix(worst, tint, a));
      return (light ? bg < inkLum : bg > inkLum) && contrastRatio(inkLum, bg) >= goal;
    }

    const max = 0.9;
    if (ok(min)) return min;
    if (!ok(max)) return max;
    var lo = min, hi = max;
    for (var i = 0; i < 14; i++) {
      final mid = (lo + hi) / 2;
      ok(mid) ? hi = mid : lo = mid;
    }
    return hi;
  }

  final shadeTint = _rgbOf(HSLColor.fromAHSL(1, hue, math.min(saturation, 0.45), 0.07).toColor());
  final veilTint = _rgbOf(HSLColor.fromAHSL(1, hue, math.min(saturation, 0.3), 0.95).toColor());
  final lightLum = luminanceOf(lightPictureInk), darkLum = luminanceOf(darkPictureInk);
  final shade = [for (var k = 0; k < stops; k++) alphaFor(bright[k], shadeTint, lightLum, target(k), light: true, min: 0.16)];
  final veil = [for (var k = 0; k < stops; k++) alphaFor(dark[k], veilTint, darkLum, target(k), light: false, min: 0.1)];
  // The lighter touch wins (the body bands count double); ties go to light text.
  double weight(List<double> a) => [for (var k = 0; k < stops; k++) a[k] * (k >= 2 && k <= 8 ? 2 : 1)].reduce((x, y) => x + y);
  final lightInk = weight(shade) <= weight(veil) + 0.3;
  final tint = lightInk ? shadeTint : veilTint;
  final ink = lightInk ? lightPictureInk : darkPictureInk;
  final worst = lightInk ? bright : dark;

  // Emphasis (also labels and active controls, at the edges): the picture's
  // own hue, light on dark or deep on light. Each band is shaded enough for
  // it too to keep 4.5:1; where even the most shade isn't enough, it moves
  // towards the ink.
  var emphasis = saturation < 0.08
      ? (lightInk ? const Color(0xFFFFE3A3) : const Color(0xFF5B3A12))
      : HSLColor.fromAHSL(1, hue, saturation.clamp(0.35, 0.7), lightInk ? 0.8 : 0.27).toColor();
  List<double> alphas() => [
        for (var k = 0; k < stops; k++)
          math.max(
            lightInk ? shade[k] : veil[k],
            alphaFor(worst[k], tint, luminanceOf(emphasis), pictureEdgeContrast, light: lightInk, min: lightInk ? 0.16 : 0.1),
          ),
      ];
  var levels = alphas();
  bool short() => [
        for (var k = 0; k < stops; k++) contrastRatio(luminanceOf(emphasis), _lum(_mix(worst[k], tint, levels[k]))) < pictureEdgeContrast,
      ].any((x) => x);
  for (var i = 0; i < 5 && short(); i++) {
    emphasis = _colorOf(_mix(_rgbOf(emphasis), _rgbOf(ink), 0.35));
    levels = alphas();
  }
  return ScenePalette(
    ink: ink,
    emphasis: emphasis,
    spot: emphasis,
    accent: emphasis,
    tint: _colorOf(tint),
    shade: [for (final a in levels) (a * 1000).ceilToDouble() / 1000],
    lightInk: lightInk,
  );
}

/// [asset]'s look on a screen of [aspect] (width ÷ height): the picture is
/// decoded small, cropped to what the screen shows (it covers the screen,
/// centred) and measured.
Future<PictureLook> lookForPicture(AssetBundle bundle, String asset, double aspect) async {
  final data = await bundle.load(asset);
  final buffer = await ui.ImmutableBuffer.fromUint8List(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
  final descriptor = await ui.ImageDescriptor.encoded(buffer);
  final size = Size(descriptor.width.toDouble(), descriptor.height.toDouble());
  final codec = await descriptor.instantiateCodec(targetWidth: math.min(64, descriptor.width));
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final w = image.width, h = image.height;
  image.dispose();
  codec.dispose();
  descriptor.dispose();
  buffer.dispose();
  var cw = w, ch = h, cx = 0, cy = 0;
  if (w / h > aspect) {
    cw = math.max(1, (h * aspect).round());
    cx = (w - cw) ~/ 2;
  } else {
    ch = math.max(1, (w / aspect).round());
    cy = (h - ch) ~/ 2;
  }
  final src = bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
  final crop = Uint8List(cw * ch * 4);
  for (var y = 0; y < ch; y++) {
    crop.setRange(y * cw * 4, (y + 1) * cw * 4, src, ((y + cy) * w + cx) * 4);
  }
  return PictureLook(paletteForPixels(crop, cw, ch), size);
}

/// A picture's look on this phone's screen shape, worked out once.
final pictureLookProvider = FutureProvider.family<PictureLook, (String, double)>(
  (ref, key) => lookForPicture(rootBundle, key.$1, key.$2),
);

/// The key for [asset] on a screen of [size] (shapes within a hundredth share a look).
(String, double) pictureLookKey(String asset, Size size) =>
    (asset, size.height <= 0 ? 0.46 : ((size.width / size.height) * 100).round() / 100);

/// The text colours for [backdrop]: a scene's tested palette, a picture's
/// measured one, or none for Paper (the reading theme's own colours).
ScenePalette? paletteFor(Backdrop backdrop, PictureLook? look) =>
    backdrop.isPicture ? look?.palette : scenePalettes[backdrop.vibe];

// ---------------------------------------------------------------- widgets

/// Decodes no larger than the screen needs: covering [screen] (physical
/// pixels), never above the picture's own [size].
ImageProvider sizedForScreen(ImageProvider image, Size? size, Size screen) {
  if (!screen.isFinite || screen.isEmpty) return image;
  if (size == null || size.isEmpty) return ResizeImage(image, height: screen.height.round(), allowUpscaling: false);
  final scale = math.max(screen.width / size.width, screen.height / size.height);
  if (scale >= 1) return image;
  return ResizeImage(image, width: (size.width * scale).ceil(), height: (size.height * scale).ceil(), allowUpscaling: false);
}

/// A backdrop at full size: the picture, covering the screen, or the painted
/// scene (Paper: the reading theme's page colour).
class BackdropView extends StatelessWidget {
  const BackdropView({super.key, required this.backdrop, this.look, this.animate = true, this.paperColor});

  final Backdrop backdrop;
  final PictureLook? look;
  final bool animate;
  final Color? paperColor;

  @override
  Widget build(BuildContext context) {
    final asset = backdrop.asset;
    if (asset == null) return VibeBackground(vibe: backdrop.vibe!, animate: animate, paperColor: paperColor);
    return LayoutBuilder(builder: (context, c) {
      final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
      return RepaintBoundary(
        child: Image(
          image: sizedForScreen(AssetImage(asset), look?.size, Size(c.maxWidth * dpr, c.maxHeight * dpr)),
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          excludeFromSemantics: true,
          errorBuilder: (_, _, _) => ColoredBox(color: paperColor ?? const Color(0xFF15161A)),
        ),
      );
    });
  }
}

/// A small tile of a backdrop, to pick it.
class BackdropThumb extends StatelessWidget {
  const BackdropThumb({
    super.key,
    required this.backdrop,
    required this.selected,
    required this.onTap,
    required this.ink,
    this.width = 44,
    this.height = 60,
    this.paperColor,
  });

  final Backdrop backdrop;
  final bool selected;
  final VoidCallback onTap;

  /// The selection ring's colour.
  final Color ink;
  final double width;
  final double height;
  final Color? paperColor;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2;
    final asset = backdrop.asset;
    final Widget art = asset != null
        ? Image(
            image: ResizeImage(AssetImage(asset), width: (width * dpr).round(), allowUpscaling: false),
            fit: BoxFit.cover,
            excludeFromSemantics: true,
            errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFF2A2A2A)),
          )
        : backdrop.isPaper
            ? ColoredBox(
                color: paperColor ?? const Color(0xFFF6F1E7),
                child: Center(
                  child: Text('Aa',
                      style: TextStyle(
                          fontFamily: 'Literata',
                          fontSize: width * 0.32,
                          color: (paperColor?.computeLuminance() ?? 1) > 0.4 ? const Color(0xFF3A352E) : const Color(0xFFE8E2D6))),
                ),
              )
            : VibeBackground(vibe: backdrop.vibe!, animate: false);
    return Semantics(
      button: true,
      selected: selected,
      label: tr('Background: {name}', {'name': backdrop.label}),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: width,
          height: height,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? ink : ink.withValues(alpha: 0.25), width: selected ? 2.5 : 1),
          ),
          child: ClipRRect(borderRadius: BorderRadius.circular(9), child: art),
        ),
      ),
    );
  }
}

/// Every backdrop in a row, Plain last: the reader's top, with the controls.
/// Opens scrolled to the one on screen.
class BackdropStrip extends StatefulWidget {
  const BackdropStrip({super.key, required this.backdrops, required this.selected, required this.onPick, required this.ink, this.paperColor});

  final List<Backdrop> backdrops;
  final Backdrop selected;
  final ValueChanged<Backdrop> onPick;
  final Color ink;
  final Color? paperColor;

  static const thumbWidth = 44.0;
  static const gap = 8.0;

  @override
  State<BackdropStrip> createState() => _BackdropStripState();
}

class _BackdropStripState extends State<BackdropStrip> {
  late final ScrollController _scroll;

  List<Backdrop> get _all => [...widget.backdrops, Backdrop.paper];

  @override
  void initState() {
    super.initState();
    final at = _all.indexOf(widget.selected);
    _scroll = ScrollController(initialScrollOffset: math.max(0, at) * (BackdropStrip.thumbWidth + BackdropStrip.gap) * 0.9);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final all = _all;
    return SizedBox(
      height: 64,
      child: ListView.separated(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        itemCount: all.length,
        separatorBuilder: (_, _) => const SizedBox(width: BackdropStrip.gap),
        itemBuilder: (context, i) => BackdropThumb(
          backdrop: all[i],
          selected: all[i] == widget.selected,
          ink: widget.ink,
          paperColor: widget.paperColor,
          onTap: () => widget.onPick(all[i]),
        ),
      ),
    );
  }
}

/// The backdrops as a grid, Plain last (the reader's options → Background).
class BackdropGrid extends StatelessWidget {
  const BackdropGrid({super.key, required this.backdrops, required this.selected, required this.onPick, this.paperColor});

  final List<Backdrop> backdrops;
  final Backdrop selected;
  final ValueChanged<Backdrop> onPick;
  final Color? paperColor;

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    final all = [...backdrops, Backdrop.paper];
    return Wrap(spacing: 10, runSpacing: 12, children: [
      for (final b in all)
        SizedBox(
          width: 76,
          child: Column(children: [
            BackdropThumb(backdrop: b, selected: b == selected, ink: kit.ink, paperColor: paperColor, width: 76, height: 104, onTap: () => onPick(b)),
            const SizedBox(height: 4),
            Text(b.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: kit.caption.copyWith(fontSize: 12, color: b == selected ? kit.ink : kit.inkSoft)),
          ]),
        ),
    ]);
  }
}
