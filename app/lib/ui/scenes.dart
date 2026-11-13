import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../data/settings.dart';

// Scenes are painted in two parts so they stay smooth on modest phones:
// * a still base (sky, hills, buildings, lamps), rendered once per scene and
//   screen size into an image ([SceneBases]) and blitted each frame;
// * a light motion layer (motes, rain, snow, stars, surf) drawn with
//   pre-blurred sprites in single atlas calls, ~30 times a second.
// Nothing blurs per frame, and the scene does not repaint while reels scroll.

/// One clock for every scene, so two pages showing the same scene (during a
/// cross-fade, say) show the same moment.
final Stopwatch _sceneWatch = Stopwatch()..start();
double get _sceneSeconds => _sceneWatch.elapsedMicroseconds / 1e6;

/// A calm, slowly moving scene. Paints in its own layer so text above it
/// never repaints with it. Still when animations are off or reduced, when its
/// route is covered and when the app is in the background.
class VibeBackground extends StatefulWidget {
  const VibeBackground({super.key, required this.vibe, this.animate = true, this.paperColor});

  final Vibe vibe;
  final bool animate;
  final Color? paperColor;

  /// Motion frames per second: plenty for drifting light, and a quarter of
  /// the work of painting at a 120 Hz refresh rate.
  static const fps = 30;

  @override
  State<VibeBackground> createState() => _VibeBackgroundState();
}

class _VibeBackgroundState extends State<VibeBackground> with WidgetsBindingObserver {
  final _clock = ValueNotifier<double>(_sceneSeconds);
  Timer? _timer;
  ValueListenable<TickerModeData>? _tickerMode;
  bool _foreground = true;
  SceneBase? _base;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final mode = TickerMode.getValuesNotifier(context);
    if (!identical(mode, _tickerMode)) {
      _tickerMode?.removeListener(_sync);
      _tickerMode = mode..addListener(_sync);
    }
    _sync();
  }

  @override
  void didUpdateWidget(VibeBackground old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  void _sync() {
    if (!mounted) return;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final run = widget.animate && !reduce && widget.vibe != Vibe.paper && (_tickerMode?.value.enabled ?? true) && _foreground;
    if (run && _timer == null) {
      _timer = Timer.periodic(const Duration(microseconds: 1000000 ~/ VibeBackground.fps), (_) => _clock.value = _sceneSeconds);
    } else if (!run && _timer != null) {
      _timer!.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tickerMode?.removeListener(_sync);
    _timer?.cancel();
    _clock.dispose();
    final base = _base;
    if (base != null) SceneBases.release(base);
    super.dispose();
  }

  /// Holds the cached base for this scene and size (full screens only:
  /// thumbnails are painted once, directly).
  ui.Image? _baseFor(Size size) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final key = size.width >= 240 ? SceneBases.keyFor(widget.vibe, size, dpr) : null;
    if (_base?.key == key) return _base?.image;
    final old = _base;
    _base = key == null ? null : SceneBases.acquire(widget.vibe, size, dpr);
    if (old != null) SceneBases.release(old);
    return _base?.image;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.vibe == Vibe.paper) {
      return ColoredBox(color: widget.paperColor ?? const Color(0xFFFBF8F1), child: const SizedBox.expand());
    }
    return LayoutBuilder(builder: (context, c) {
      final size = c.biggest;
      final base = size.isFinite ? _baseFor(size) : null;
      return RepaintBoundary(
        child: CustomPaint(
          size: size,
          painter: ScenePainter(widget.vibe, () => _clock.value, repaint: _clock, base: base),
        ),
      );
    });
  }
}

/// Paints one scene: its still base (from [base] when cached) and its motion
/// at [seconds].
class ScenePainter extends CustomPainter {
  ScenePainter(this.vibe, this.seconds, {super.repaint, this.base});

  final Vibe vibe;
  final double Function() seconds;
  final ui.Image? base;

  static final _blit = Paint()..filterQuality = FilterQuality.low;

  /// How many times any scene has painted (for tests of the frame rate).
  static int debugPaintCount = 0;

  @override
  void paint(Canvas canvas, Size size) {
    assert(() {
      debugPaintCount++;
      return true;
    }());
    final image = base;
    if (image != null) {
      canvas.drawImageRect(image, Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()), Offset.zero & size, _blit);
    } else {
      paintSceneBase(vibe, canvas, size);
    }
    paintSceneMotion(vibe, canvas, size, seconds());
  }

  @override
  bool shouldRepaint(ScenePainter old) => old.vibe != vibe || old.base != base;
}

/// A cached base image, shared by every background showing that scene at
/// that size.
class SceneBase {
  SceneBase._(this.key, this.image);
  final String key;
  final ui.Image image;
  int _users = 0;
}

/// Reference-counted cache of scene bases. Unused bases are kept for a
/// moment (switching scenes back and forth) and then freed.
abstract final class SceneBases {
  static final Map<String, SceneBase> _all = {};
  static final List<String> _idle = [];
  static const _keepIdle = 2;

  static String? keyFor(Vibe vibe, Size size, double dpr) {
    final w = (size.width * dpr).round(), h = (size.height * dpr).round();
    if (vibe == Vibe.paper || w <= 0 || h <= 0 || w * h > 16000000) return null;
    return '${vibe.name}:${w}x$h';
  }

  static SceneBase? acquire(Vibe vibe, Size size, double dpr) {
    final key = keyFor(vibe, size, dpr);
    if (key == null) return null;
    var base = _all[key];
    if (base == null) {
      final rec = ui.PictureRecorder();
      final c = Canvas(rec)..scale(dpr);
      paintSceneBase(vibe, c, size);
      final picture = rec.endRecording();
      base = SceneBase._(key, picture.toImageSync((size.width * dpr).round(), (size.height * dpr).round()));
      picture.dispose();
      _all[key] = base;
    }
    _idle.remove(key);
    base._users++;
    return base;
  }

  static void release(SceneBase base) {
    if (--base._users > 0) return;
    _idle.add(base.key);
    while (_idle.length > _keepIdle) {
      _all.remove(_idle.removeAt(0))?.image.dispose();
    }
  }
}

void paintSceneBase(Vibe vibe, Canvas c, Size size) {
  switch (vibe) {
    case Vibe.forest:
      _forestBase(c, size);
    case Vibe.cafe:
      _cafeBase(c, size);
    case Vibe.rain:
      _rainBase(c, size);
    case Vibe.ocean:
      _oceanBase(c, size);
    case Vibe.night:
      _nightBase(c, size);
    case Vibe.meadow:
      _meadowBase(c, size);
    case Vibe.snow:
      _snowBase(c, size);
    case Vibe.city:
      _cityBase(c, size);
    case Vibe.paper:
      c.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFFBF8F1));
  }
}

void paintSceneMotion(Vibe vibe, Canvas c, Size size, double t) {
  switch (vibe) {
    case Vibe.forest:
      _forestMotion(c, size, t);
    case Vibe.cafe:
      _cafeMotion(c, size, t);
    case Vibe.rain:
      _rainMotion(c, size, t);
    case Vibe.ocean:
      _oceanMotion(c, size, t);
    case Vibe.night:
      _nightMotion(c, size, t);
    case Vibe.meadow:
      _meadowMotion(c, size, t);
    case Vibe.snow:
      _snowMotion(c, size, t);
    case Vibe.city:
      _cityMotion(c, size, t);
    case Vibe.paper:
      break;
  }
}

// --------------------------------------------------------------------------
// Sprites: soft shapes blurred once, then stamped many times per frame.

ui.Image _sprite(int w, int h, void Function(Canvas c) draw) {
  final rec = ui.PictureRecorder();
  draw(Canvas(rec));
  final picture = rec.endRecording();
  final image = picture.toImageSync(w, h);
  picture.dispose();
  return image;
}

const _white = Color(0xFFFFFFFF);

/// A soft round glow: a disc of radius 13 blurred by 6, in a 64 px square.
final ui.Image _dot = _sprite(
    64, 64, (c) => c.drawCircle(const Offset(32, 32), 13, Paint()..color = _white..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6)));

/// Visual radius of [_dot] (disc plus most of its glow).
const _dotRadius = 25.0;

/// A soft horizontal glint, 40 px long in a 64 x 16 px tile.
final ui.Image _glint = _sprite(64, 16, (c) {
  c.drawLine(
      const Offset(12, 8),
      const Offset(52, 8),
      Paint()
        ..color = _white
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.6));
});

/// A soft cloud: an oval blurred by 12 in a 256 x 64 px tile.
final ui.Image _cloud = _sprite(
    256, 64, (c) => c.drawOval(const Rect.fromLTWH(40, 16, 176, 32), Paint()..color = _white..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12)));

/// Batches sprite stamps into one [Canvas.drawRawAtlas] call.
class _Stamps {
  _Stamps(int capacity)
      : _xf = Float32List(capacity * 4),
        _rects = Float32List(capacity * 4),
        _colors = Int32List(capacity);

  final Float32List _xf;
  final Float32List _rects;
  final Int32List _colors;
  int _n = 0;
  static final _paint = Paint()..filterQuality = FilterQuality.low;

  /// Stamps [image]'s [src] centred on (x, y), scaled by [scale], tinted [color].
  void add(double x, double y, double scale, Color color, Rect src) {
    if (_n * 4 >= _xf.length) return;
    final i = _n * 4;
    _xf[i] = scale;
    _xf[i + 1] = 0;
    _xf[i + 2] = x - scale * src.width / 2;
    _xf[i + 3] = y - scale * src.height / 2;
    _rects[i] = src.left;
    _rects[i + 1] = src.top;
    _rects[i + 2] = src.right;
    _rects[i + 3] = src.bottom;
    _colors[_n] = color.toARGB32();
    _n++;
  }

  void draw(Canvas c, ui.Image image) {
    if (_n == 0) return;
    c.drawRawAtlas(image, Float32List.sublistView(_xf, 0, _n * 4), Float32List.sublistView(_rects, 0, _n * 4),
        Int32List.sublistView(_colors, 0, _n), BlendMode.modulate, null, _paint);
    _n = 0;
  }
}

final _stamps = _Stamps(160);
const _dotSrc = Rect.fromLTWH(0, 0, 64, 64);
const _glintSrc = Rect.fromLTWH(0, 0, 64, 16);

/// A soft dot whose glow reaches about [radius].
void _glowDot(double x, double y, double radius, Color color) => _stamps.add(x, y, radius / _dotRadius, color, _dotSrc);

/// Draws many straight lines (rain) in one call.
final Float32List _lineBuffer = Float32List(160 * 4);
void _lines(Canvas c, int n, void Function(int i, Float32List out, int at) line, Paint paint) {
  final count = math.min(n, _lineBuffer.length ~/ 4);
  for (var i = 0; i < count; i++) {
    line(i, _lineBuffer, i * 4);
  }
  c.drawRawPoints(ui.PointMode.lines, Float32List.sublistView(_lineBuffer, 0, count * 4), paint);
}

// --------------------------------------------------------------------------
// Shared helpers

final _rand = math.Random(7);
final List<List<double>> _seeds = List.generate(160, (_) => List.generate(4, (_) => _rand.nextDouble()));

void _gradient(Canvas c, Size size, List<Color> colors, List<double> stops) {
  c.drawRect(
    Offset.zero & size,
    Paint()
      ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: colors, stops: stops)
          .createShader(Offset.zero & size),
  );
}

void _glow(Canvas c, Offset center, double radius, Color color) {
  c.drawCircle(
    center,
    radius,
    Paint()..shader = RadialGradient(colors: [color, color.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: center, radius: radius)),
  );
}

void _band(Canvas c, Rect r, Color middle) {
  c.drawRect(
    r,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [middle.withValues(alpha: 0), middle, middle.withValues(alpha: 0)],
      ).createShader(r),
  );
}

final Map<String, Path> _pathCache = {};

Path _cached(String key, Path Function() build) => _pathCache.putIfAbsent(key, build);

Path _pineRidge(Size size, int seed, double baseY, double minH, double maxH, double spacing) {
  final r = math.Random(seed);
  final p = Path()..moveTo(0, size.height);
  p.lineTo(0, baseY);
  var x = 0.0;
  while (x < size.width + spacing) {
    final h = minH + r.nextDouble() * (maxH - minH);
    final w = h * 0.34;
    for (var tier = 0; tier < 4; tier++) {
      final top = baseY - h + tier * h * 0.2;
      final bottom = top + h * 0.38;
      final half = w * (0.45 + tier * 0.18);
      p.moveTo(x - half, bottom);
      p.lineTo(x, top);
      p.lineTo(x + half, bottom);
      p.close();
    }
    p.addRect(Rect.fromLTRB(x - w * 0.06, baseY - h * 0.15, x + w * 0.06, baseY + 2));
    x += spacing * (0.6 + r.nextDouble() * 0.8);
  }
  // Overlap the lowest branches so no sky shows between trunks.
  p.addRect(Rect.fromLTRB(0, baseY - size.height * 0.012, size.width + spacing, size.height));
  return p;
}

Path _mountains(Size size, int seed, double baseY, double amp, int peaks) {
  final r = math.Random(seed);
  final p = Path()..moveTo(0, size.height);
  p.lineTo(0, baseY);
  final step = size.width / peaks;
  for (var i = 0; i <= peaks; i++) {
    final x = i * step;
    final peakY = baseY - amp * (0.4 + r.nextDouble() * 0.6);
    p.lineTo(x + step * 0.5, peakY);
    p.lineTo(x + step, baseY - amp * r.nextDouble() * 0.3);
  }
  p.lineTo(size.width, size.height);
  p.close();
  return p;
}

// --------------------------------------------------------------------------
// Forest morning: sun through the pines, mist, motes drifting in the light.

void _forestBase(Canvas c, Size size) {
  final w = size.width, h = size.height;
  // A pale morning sky, warm low down where the sun comes through.
  _gradient(c, size, const [Color(0xFFC2DCE2), Color(0xFFDDEBE2), Color(0xFFF3EFD8), Color(0xFFE6EBD6), Color(0xFFD3DFC8)],
      const [0, 0.18, 0.36, 0.62, 1]);
  final sun = _forestSun(size);
  _glow(c, sun, w * 0.8, const Color(0xB3FFF4D2));
  // Sunbeams slanting down through the trees.
  for (var i = 0; i < 4; i++) {
    final angle = 1.98 + i * 0.15, spread = 0.03 + (i.isEven ? 0.014 : 0), len = h * 1.1;
    final beam = Path()
      ..moveTo(sun.dx, sun.dy)
      ..lineTo(sun.dx + math.cos(angle - spread) * len, sun.dy + math.sin(angle - spread) * len)
      ..lineTo(sun.dx + math.cos(angle + spread) * len, sun.dy + math.sin(angle + spread) * len)
      ..close();
    c.drawPath(
        beam,
        Paint()
          ..shader = RadialGradient(colors: const [Color(0x40FFF8DE), Color(0x00FFF8DE)])
              .createShader(Rect.fromCircle(center: sun, radius: len)));
  }
  c.drawCircle(sun, 22, Paint()..color = const Color(0xFFFFFAE8));
  // Pines fade into the mist with distance, so the middle of the screen
  // stays light behind dark text.
  const layers = [
    (Color(0xFFBDD1C1), 0.40, 0.10, 0.20),
    (Color(0xFFA5C0AA), 0.54, 0.12, 0.24),
    (Color(0xFF92B198), 0.70, 0.12, 0.20),
    (Color(0xFF6A9073), 0.93, 0.08, 0.14),
  ];
  for (var i = 0; i < layers.length; i++) {
    final (color, base, minH, maxH) = layers[i];
    final path = _cached('forest$i-${w.round()}x${h.round()}',
        () => _pineRidge(size, 11 + i, h * base, h * minH, h * maxH, w * (0.16 - i * 0.02)));
    c.drawPath(path, Paint()..color = color);
    // Morning mist lying in front of each ridge.
    if (i < 3) _band(c, Rect.fromLTWH(0, h * (base + 0.02) - h * 0.07, w, h * 0.14), const Color(0x70F6F8EE));
  }
}

Offset _forestSun(Size size) => Offset(size.width * 0.76, size.height * 0.14);

void _forestMotion(Canvas c, Size size, double t) {
  final w = size.width, h = size.height;
  // Motes of pollen and dust drifting down through the sunlight.
  for (var i = 0; i < 30; i++) {
    final sd = _seeds[i];
    final fall = (t * (4 + sd[2] * 6) + sd[1] * h * 0.8) % (h * 0.8);
    final x = sd[0] * w + math.sin(t * 0.3 + sd[3] * 6) * 22;
    final y = h * 0.1 + fall;
    final a = 0.35 + 0.65 * (0.5 + 0.5 * math.sin(t * 1.1 + sd[3] * 10));
    _glowDot(x, y, 5 + sd[2] * 2.5, Color.fromRGBO(255, 251, 230, a * 0.85));
  }
  _stamps.draw(c, _dot);
}

// --------------------------------------------------------------------------
// Café: a rainy window, pendant lights, a steaming cup.

RRect _cafeWindow(Size size) =>
    RRect.fromRectAndRadius(Rect.fromLTWH(size.width * 0.08, size.height * 0.12, size.width * 0.84, size.height * 0.46), const Radius.circular(18));

Offset _cafeLamp(Size size, int i) =>
    Offset(size.width * const [0.165, 0.64, 0.895][i], size.height * (0.118 + (i.isEven ? 0.018 : 0)));

void _cafeBase(Canvas c, Size size) {
  final w = size.width, h = size.height;
  _gradient(c, size, const [Color(0xFF2A1C15), Color(0xFF3F2A20), Color(0xFF4E3426)], const [0, 0.6, 1]);
  // Window with a rainy city outside: its lights soft through the glass.
  final win = _cafeWindow(size);
  c.save();
  c.clipRRect(win);
  c.drawRect(
    win.outerRect,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF16233A), Color(0xFF2C4263)],
      ).createShader(win.outerRect),
  );
  final bokeh = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
  const warm = [Color(0xFFFFB86B), Color(0xFFFFD9A0), Color(0xFF8FB6FF), Color(0xFFFF8F70)];
  for (var i = 0; i < 18; i++) {
    final sd = _seeds[i + 30];
    final x = win.left + sd[0] * win.width;
    final y = win.top + win.height * (0.45 + sd[1] * 0.5);
    c.drawCircle(Offset(x, y), 8 + sd[2] * 16, bokeh..color = warm[i % warm.length].withValues(alpha: 0.35));
  }
  c.restore();
  final frame = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 10
    ..color = const Color(0xFF1C130E);
  c.drawRRect(win, frame);
  c.drawLine(Offset(win.center.dx, win.top), Offset(win.center.dx, win.bottom), frame..strokeWidth = 6);
  // Pendant lamps: cords and bulbs (their glow moves, see below). Bulbs hang
  // below the reader's top bar, cords between its controls.
  for (var i = 0; i < 3; i++) {
    final lamp = _cafeLamp(size, i);
    c.drawLine(Offset(lamp.dx, 0), lamp, Paint()
      ..color = const Color(0xFF120C08)
      ..strokeWidth = 2);
    c.drawCircle(lamp.translate(0, 8), 7, Paint()..color = const Color(0xFFFFE3AE));
  }
  // Table and a cup.
  final table = Rect.fromLTWH(0, h * 0.84, w, h * 0.16);
  c.drawRect(
    table,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF6A4630), Color(0xFF3A2619)],
      ).createShader(table),
  );
  final cup = Offset(w * 0.78, h * 0.84);
  c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cup.dx - 24, cup.dy - 40, 48, 40), const Radius.circular(10)),
      Paint()..color = const Color(0xFF9C7E64));
  c.drawCircle(Offset(cup.dx + 28, cup.dy - 22), 9, Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 5
    ..color = const Color(0xFF9C7E64));
}

final _cafeRain = Paint()
  ..color = const Color(0x40FFFFFF)
  ..strokeWidth = 1.2;
final _steam = Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = 3
  ..strokeCap = StrokeCap.round;

void _cafeMotion(Canvas c, Size size, double t) {
  final w = size.width, h = size.height;
  // Rain running down the glass (inside the frame).
  final win = _cafeWindow(size).deflate(5);
  c.save();
  c.clipRRect(win);
  _lines(c, 60, (i, out, at) {
    final sd = _seeds[i + 50];
    final y = win.top + ((sd[1] * win.height + t * (160 + sd[2] * 120)) % win.height);
    final x = win.left + sd[0] * win.width;
    out[at] = x;
    out[at + 1] = y;
    out[at + 2] = x - 3;
    out[at + 3] = y + 12 + sd[3] * 8;
  }, _cafeRain);
  c.restore();
  // The lamps' soft flicker.
  for (var i = 0; i < 3; i++) {
    final flicker = 0.85 + 0.15 * math.sin(t * 2.3 + i * 2);
    _glow(c, _cafeLamp(size, i).translate(0, 8), 90, Color.fromRGBO(255, 205, 140, 0.32 * flicker));
  }
  // Steam from the cup.
  final cup = Offset(w * 0.78, h * 0.84);
  for (var i = 0; i < 3; i++) {
    final phase = (t * 0.35 + i / 3) % 1.0;
    final base = Offset(cup.dx - 12 + i * 12, cup.dy - 46);
    final path = Path()..moveTo(base.dx, base.dy);
    for (var k = 1; k <= 6; k++) {
      final y = base.dy - k * 9 - phase * 20;
      path.lineTo(base.dx + math.sin(k * 0.9 + t * 1.2 + i) * 6, y);
    }
    c.drawPath(path, _steam..color = Color.fromRGBO(255, 255, 255, 0.28 * (1 - phase)));
  }
}

// --------------------------------------------------------------------------
// Rain: city lights through a wet window.

void _rainBase(Canvas c, Size size) {
  final w = size.width, h = size.height;
  _gradient(c, size, const [Color(0xFF0D1626), Color(0xFF182A42), Color(0xFF22384F)], const [0, 0.55, 1]);
  final bokeh = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
  const colors = [Color(0xFFFFC27A), Color(0xFF7FB2FF), Color(0xFFFF8FA3), Color(0xFFFFE6A8)];
  for (var i = 0; i < 26; i++) {
    final sd = _seeds[i + 70];
    final x = sd[0] * w;
    final y = h * (0.35 + sd[1] * 0.6);
    c.drawCircle(Offset(x, y), 10 + sd[2] * 24, bokeh..color = colors[i % colors.length].withValues(alpha: 0.18));
  }
}

final _rainStreak = Paint()
  ..color = const Color(0x30BFD6F2)
  ..strokeWidth = 1.1;
final _drop = Paint()..color = const Color(0x22D8E8FF);
final _dropShine = Paint()..color = const Color(0x55FFFFFF);

void _rainMotion(Canvas c, Size size, double t) {
  final w = size.width, h = size.height;
  _lines(c, 110, (i, out, at) {
    final sd = _seeds[i % 160];
    final speed = 260 + sd[2] * 220;
    final y = ((sd[1] * h + t * speed + i * 37) % (h + 40)) - 20;
    final x = (sd[0] * w + i * 13) % w;
    out[at] = x;
    out[at + 1] = y;
    out[at + 2] = x - 4;
    out[at + 3] = y + 16 + sd[3] * 10;
  }, _rainStreak);
  // Droplets sliding down the glass.
  for (var i = 0; i < 22; i++) {
    final sd = _seeds[i + 100];
    final y = (sd[1] * h + t * (3 + sd[2] * 6)) % h;
    final o = Offset(sd[0] * w, y);
    final r = 2.5 + sd[3] * 3.5;
    c.drawCircle(o, r, _drop);
    c.drawCircle(o.translate(-r * 0.3, -r * 0.3), r * 0.35, _dropShine);
  }
}

// --------------------------------------------------------------------------
// Beach: a bright shore, slow surf washing up the sand.

double _beachHorizon(Size s) => s.height * 0.5;
double _beachShore(Size s) => s.height * 0.76;

void _oceanBase(Canvas c, Size size) {
  final w = size.width, h = size.height;
  final horizon = _beachHorizon(size), shore = _beachShore(size);
  _gradient(c, Size(w, horizon), const [Color(0xFF8DC9EE), Color(0xFFBFE2F5), Color(0xFFE5F3F8)], const [0, 0.55, 1]);
  final sun = Offset(w * 0.78, h * 0.1);
  _glow(c, sun, w * 0.6, const Color(0xB3FFF6D8));
  c.drawCircle(sun, 24, Paint()..color = const Color(0xFFFFFBEA));
  // The sea: deeper blue at the horizon, turquoise towards the shore.
  final sea = Rect.fromLTWH(0, horizon, w, shore - horizon + h * 0.02);
  c.drawRect(
    sea,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF79B9D9), Color(0xFF8FD2DB), Color(0xFFB2E3DC)],
      ).createShader(sea),
  );
  // A soft haze on the horizon, so no hard line runs behind the text.
  _band(c, Rect.fromLTWH(0, horizon - h * 0.025, w, h * 0.05), const Color(0x99EEF8FA));
  // Sand, with a gently curving water line.
  final sand = _cached('beach-${w.round()}x${h.round()}', () {
    final p = Path()..moveTo(0, h);
    for (var x = 0.0; x <= w + 8; x += 8) {
      p.lineTo(x, shore + math.sin(x / w * math.pi * 2 + 0.6) * h * 0.008);
    }
    return p
      ..lineTo(w + 8, h)
      ..close();
  });
  c.drawPath(
    sand,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFE4D6B4), Color(0xFFF2E6C8), Color(0xFFEEDDB6)],
        stops: [0, 0.3, 1],
      ).createShader(Rect.fromLTWH(0, shore, w, h - shore)),
  );
}

const _cloudSrc = Rect.fromLTWH(0, 0, 256, 64);
final _beachCloud = Paint()
  ..filterQuality = FilterQuality.low
  ..colorFilter = const ColorFilter.mode(Color(0xE6FFFFFF), BlendMode.modulate);
final _wash = Paint()..color = const Color(0x99D3F1EC);
final _foam = Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = 2.5
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..color = const Color(0xF2FFFFFF);
final _gull = Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = 1.6
  ..strokeCap = StrokeCap.round
  ..color = const Color(0x8C5A6B78);

void _oceanMotion(Canvas c, Size size, double t) {
  final w = size.width, h = size.height;
  final horizon = _beachHorizon(size), shore = _beachShore(size);
  // Clouds drifting across the sky.
  for (var i = 0; i < 5; i++) {
    final sd = _seeds[i + 120];
    final x = (sd[0] * w + t * (3 + sd[2] * 4)) % (w + 240) - 120;
    final cw = 150 + sd[3] * 130, ch = 22 + sd[2] * 16;
    // The sprite's oval fills 176 x 32 of its 256 x 64 tile.
    final dst = Rect.fromCenter(center: Offset(x, horizon * (0.14 + sd[1] * 0.62)), width: cw * 256 / 176, height: ch * 64 / 32);
    c.drawImageRect(_cloud, _cloudSrc, dst, _beachCloud);
  }
  // Two gulls gliding high above the shore (above the text).
  for (var i = 0; i < 2; i++) {
    final sd = _seeds[i + 150];
    final x = (sd[0] * w + t * (9 + sd[2] * 6)) % (w + 80) - 40;
    final y = h * (0.07 + sd[1] * 0.07) + math.sin(t * 0.5 + i) * 5;
    final flap = math.sin(t * 2.6 + i * 2) * 2.5, s = 7 + sd[3] * 3;
    c.drawPath(
        Path()
          ..moveTo(x - s, y - 2 + flap)
          ..quadraticBezierTo(x - s * 0.4, y - 4 + flap, x, y)
          ..quadraticBezierTo(x + s * 0.4, y - 4 + flap, x + s, y - 2 + flap),
        _gull);
  }
  // Sunlight glinting on the water.
  for (var i = 0; i < 36; i++) {
    final sd = _seeds[i];
    final y = horizon + 6 + sd[1] * (shore - horizon - 12);
    final x = sd[0] * w + math.sin(t * 0.7 + sd[3] * 6) * 8;
    final a = 0.12 + 0.6 * math.max(0.0, math.sin(t * 1.4 + sd[2] * 9));
    // The glint is 40 px long in its tile.
    _stamps.add(x, y, (10 + sd[2] * 16) / 40, Color.fromRGBO(255, 255, 255, a), _glintSrc);
  }
  _stamps.draw(c, _glint);
  // Waves washing up the sand and sliding back, one after the other.
  for (var k = 0; k < 2; k++) {
    final swell = 0.5 + 0.5 * math.sin(t * 0.42 + k * math.pi);
    final reach = shore + h * (0.004 + 0.034 * swell);
    final wave = Path()..moveTo(0, shore - h * 0.01);
    final front = Path();
    for (var x = 0.0; x <= w + 8; x += 8) {
      final y = reach + math.sin(x / w * math.pi * 3 + k * 2 + t * 0.2) * h * 0.006;
      wave.lineTo(x, y);
      x == 0 ? front.moveTo(x, y) : front.lineTo(x, y);
    }
    wave
      ..lineTo(w + 8, shore - h * 0.01)
      ..close();
    c.drawPath(wave, _wash);
    c.drawPath(front, _foam);
  }
}

// --------------------------------------------------------------------------
// Night: stars over the mountains.

void _nightBase(Canvas c, Size size) {
  final w = size.width, h = size.height;
  _gradient(c, size, const [Color(0xFF080C20), Color(0xFF161D40), Color(0xFF2B2B5A)], const [0, 0.6, 1]);
  final moon = Offset(w * 0.8, h * 0.145);
  _glow(c, moon, 96, const Color(0x40E8E6FF));
  c.drawCircle(moon, 18, Paint()..color = const Color(0xFFF4F1E0));
  c.drawCircle(moon.translate(7, -4), 16, Paint()..color = const Color(0xFF12183A).withValues(alpha: 0.9));
  const ridges = [(Color(0xFF2A2F5C), 0.66, 0.16), (Color(0xFF1C2046), 0.76, 0.14), (Color(0xFF10132E), 0.88, 0.12)];
  for (var i = 0; i < ridges.length; i++) {
    final (color, base, amp) = ridges[i];
    final path = _cached('night$i-${w.round()}x${h.round()}', () => _mountains(size, 31 + i, h * base, h * amp, 5 + i * 2));
    c.drawPath(path, Paint()..color = color);
    if (i == 0) _band(c, Rect.fromLTWH(0, h * (base + 0.03) - h * 0.05, w, h * 0.1), const Color(0x22B8B8FF));
  }
}

void _nightMotion(Canvas c, Size size, double t) {
  final w = size.width, h = size.height;
  // Stars twinkle in the open sky above the highest ridge (half the screen).
  for (var i = 0; i < 130; i++) {
    final sd = _seeds[i % 160];
    final x = ((sd[0] + i * 0.0137) % 1) * w;
    final y = ((sd[1] + i * 0.0071) % 1) * h * 0.5;
    final a = 0.25 + 0.75 * (0.5 + 0.5 * math.sin(t * (0.8 + sd[2] * 1.6) + sd[3] * 12));
    // Bright in the open sky, faint behind the text (a star must never read as a full stop).
    final band = 1 - 0.62 * ((y / h - 0.22) / 0.2).clamp(0.0, 1.0);
    _glowDot(x, y, (0.6 + sd[2] * 1.3) * 2.2, Color.fromRGBO(255, 255, 255, a * band));
  }
  _stamps.draw(c, _dot);
  // An occasional shooting star (every ~16 s).
  final cycle = t % 16;
  if (cycle < 1.2) {
    final p = cycle / 1.2;
    final start = Offset(w * 0.12, h * 0.13);
    final head = start + Offset(w * 0.42 * p, h * 0.08 * p);
    c.drawLine(head - Offset(w * 0.08, h * 0.02), head, Paint()
      ..shader = LinearGradient(colors: [const Color(0x00FFFFFF), Color.fromRGBO(255, 255, 255, 0.9 * (1 - p))])
          .createShader(Rect.fromPoints(head - Offset(w * 0.08, h * 0.02), head))
      ..strokeWidth = 2);
  }
}

// --------------------------------------------------------------------------
// Meadow: a sunny day, drifting clouds.

void _meadowBase(Canvas c, Size size) {
  final w = size.width, h = size.height;
  _gradient(c, size, const [Color(0xFF7FB8EA), Color(0xFFBFE1F5), Color(0xFFF7EFD6)], const [0, 0.42, 0.62]);
  _glow(c, Offset(w * 0.22, h * 0.16), w * 0.6, const Color(0xB3FFF8E1));
  c.drawCircle(Offset(w * 0.22, h * 0.16), 26, Paint()..color = const Color(0xFFFFF6D5));
  // Rolling hills.
  const hills = [(Color(0xFFB4D98F), 0.60, 22.0), (Color(0xFF8CC271), 0.70, 28.0), (Color(0xFF64A257), 0.82, 34.0)];
  for (var i = 0; i < hills.length; i++) {
    final (color, base, amp) = hills[i];
    final path = _cached('meadow$i-${w.round()}x${h.round()}', () {
      final periods = const [1, 2, 1][i];
      final p = Path()..moveTo(0, h);
      for (var x = 0.0; x <= w + 4; x += 4) {
        p.lineTo(x, h * base + math.sin(x / w * math.pi * 2 * periods + i) * amp + math.sin(x / w * math.pi * 6 + i * 2) * amp * 0.25);
      }
      p.lineTo(w + 4, h);
      p.close();
      return p;
    });
    c.drawPath(path, Paint()..color = color);
  }
  // Flowers on the near hill.
  const petals = [Color(0xFFFFD166), Color(0xFFFF8FA3), Color(0xFFFFFFFF), Color(0xFFC3A6FF)];
  for (var i = 0; i < 40; i++) {
    final sd = _seeds[i + 60];
    c.drawCircle(Offset(sd[0] * w, h * (0.86 + sd[1] * 0.13)), 2.2 + sd[2] * 2, Paint()..color = petals[i % petals.length]);
  }
}

final _meadowCloud = Paint()..color = const Color(0xE6FFFFFF);

void _meadowMotion(Canvas c, Size size, double t) {
  final w = size.width, h = size.height;
  // Fluffy clouds drifting right.
  for (var i = 0; i < 5; i++) {
    final sd = _seeds[i + 140];
    final x = (sd[0] * w + t * (4 + sd[2] * 6)) % (w + 220) - 110;
    final y = h * (0.08 + sd[1] * 0.3);
    final r = 18 + sd[3] * 16;
    for (var k = 0; k < 5; k++) {
      c.drawCircle(Offset(x + (k - 2) * r * 0.9, y + (k.isEven ? 0 : -r * 0.45)), r * (k == 2 ? 1.25 : 0.95), _meadowCloud);
    }
  }
  // Floating pollen.
  for (var i = 0; i < 24; i++) {
    final sd = _seeds[i + 90];
    final x = (sd[0] * w + t * (8 + sd[2] * 10)) % w;
    final y = h * (0.3 + sd[1] * 0.5) + math.sin(t * 0.7 + sd[3] * 7) * 14;
    _glowDot(x, y, 3, const Color(0xCCFFFBE6));
  }
  _stamps.draw(c, _dot);
}

// --------------------------------------------------------------------------
// Snow day: white hills under a pale sky, a cabin, soft snowfall.

void _snowBase(Canvas c, Size size) {
  final w = size.width, h = size.height;
  _gradient(c, size, const [Color(0xFFAACCEB), Color(0xFFD0E4F3), Color(0xFFEAF2F9), Color(0xFFF3F7FB)], const [0, 0.3, 0.55, 0.8]);
  final sun = Offset(w * 0.24, h * 0.12);
  _glow(c, sun, w * 0.6, const Color(0x99FFFBEA));
  c.drawCircle(sun, 20, Paint()..color = const Color(0xFFFFFCF0));
  // Far snowy mountains, nearer white foothills, then frosted pines.
  c.drawPath(_cached('snowridge-${w.round()}x${h.round()}', () => _mountains(size, 51, h * 0.64, h * 0.16, 6)),
      Paint()..color = const Color(0xFFC9D8E9));
  c.drawPath(_cached('snowhills-${w.round()}x${h.round()}', () => _mountains(size, 52, h * 0.72, h * 0.07, 4)),
      Paint()..color = const Color(0xFFE2EAF4));
  c.drawPath(_cached('snowpines-${w.round()}x${h.round()}', () => _pineRidge(size, 61, h * 0.85, h * 0.06, h * 0.12, w * 0.12)),
      Paint()..color = const Color(0xFF93AEB2));
  // The snowfield, with soft blue drifts.
  final ground = Path()..moveTo(0, h);
  for (var x = 0.0; x <= w + 1; x += 10) {
    ground.lineTo(x, h * 0.86 + math.sin(x / w * math.pi * 2) * 8);
  }
  ground
    ..lineTo(w, h)
    ..close();
  c.drawPath(ground, Paint()..color = const Color(0xFFF6F9FC));
  final drift = Path()..moveTo(0, h);
  for (var x = 0.0; x <= w + 1; x += 10) {
    drift.lineTo(x, h * 0.93 + math.sin(x / w * math.pi * 3 + 1) * 10);
  }
  drift
    ..lineTo(w, h)
    ..close();
  c.drawPath(drift, Paint()..color = const Color(0xFFE6EEF7));
  // A wooden cabin, its roof deep in snow.
  final base = _snowCabin(size);
  c.drawRect(Rect.fromLTWH(base.dx - 40, base.dy - 46, 80, 46), Paint()..color = const Color(0xFFAD7B57));
  c.drawRect(Rect.fromLTWH(base.dx + 18, base.dy - 78, 10, 26), Paint()..color = const Color(0xFFB3ABA4));
  // The roof, deep in snow, with a thin eave of wood showing.
  final roof = Path()
    ..moveTo(base.dx - 56, base.dy - 43)
    ..lineTo(base.dx, base.dy - 86)
    ..lineTo(base.dx + 56, base.dy - 43)
    ..close();
  c.drawPath(roof, Paint()..color = const Color(0xFFFBFDFF));
  c.drawLine(Offset(base.dx - 54, base.dy - 43), Offset(base.dx + 54, base.dy - 43), Paint()
    ..color = const Color(0xFF8A5E43)
    ..strokeWidth = 3);
  c.drawRect(Rect.fromLTWH(base.dx - 22, base.dy - 34, 20, 18), Paint()..color = const Color(0xFFF5CF84));
}

Offset _snowCabin(Size size) => Offset(size.width * 0.68, size.height * 0.86);

void _snowMotion(Canvas c, Size size, double t) {
  final w = size.width, h = size.height;
  final base = _snowCabin(size);
  // Chimney smoke: soft grey puffs that rise and fade.
  for (var i = 0; i < 4; i++) {
    final phase = (t * 0.12 + i / 4) % 1.0;
    final y = base.dy - 82 - phase * 90;
    final x = base.dx + 23 + math.sin(phase * 6 + t * 0.6) * 10 + phase * 18;
    c.drawCircle(Offset(x, y), 6 + phase * 10, Paint()..color = Color.fromRGBO(168, 180, 196, 0.32 * (1 - phase)));
  }
  // Snow falling softly: white flakes show against the hills and pines,
  // pale blue-grey ones against the bright sky.
  for (var i = 0; i < 110; i++) {
    final sd = _seeds[i % 160];
    final speed = 14 + sd[2] * 22;
    final y = ((sd[1] * h + t * speed + i * 23) % (h + 20)) - 10;
    final x = ((sd[0] * w + i * 17) % w) + math.sin(t * 0.7 + sd[3] * 10) * 14;
    final onSky = y < h * 0.6;
    final colour = onSky ? Color.fromRGBO(176, 194, 218, 0.4 + sd[2] * 0.25) : Color.fromRGBO(255, 255, 255, 0.6 + sd[2] * 0.35);
    _glowDot(x, y, (0.9 + sd[3] * 2.0) * 1.7, colour);
  }
  _stamps.draw(c, _dot);
}

// --------------------------------------------------------------------------
// City: skyline lights at night.

final Map<String, List<Rect>> _rectCache = {};

List<Rect> _skyline(Size size, int seed, double baseY, double minH, double maxH) =>
    _rectCache.putIfAbsent('sky$seed-${size.width.round()}x${size.height.round()}', () {
      final r = math.Random(seed);
      final out = <Rect>[];
      var x = 0.0;
      while (x < size.width + 40) {
        final bw = 28 + r.nextDouble() * 46;
        final bh = minH + r.nextDouble() * (maxH - minH);
        out.add(Rect.fromLTWH(x, baseY - bh, bw, bh + size.height - baseY));
        x += bw + r.nextDouble() * 6;
      }
      return out;
    });

void _cityBase(Canvas c, Size size) {
  final w = size.width, h = size.height;
  _gradient(c, size, const [Color(0xFF0D0A28), Color(0xFF261443), Color(0xFF6A2C5E), Color(0xFF1A1030)], const [0, 0.42, 0.66, 0.9]);
  _glow(c, Offset(w * 0.5, h * 0.72), w * 0.9, const Color(0x30FF7AB8));
  void layer(List<Rect> rects, Color color, {bool windows = false}) {
    for (var i = 0; i < rects.length; i++) {
      final b = rects[i];
      if (b.left > w) continue;
      c.drawRect(b, Paint()..color = color);
      if (!windows) continue;
      final lit = Paint();
      for (var wy = b.top + 8; wy < h * 0.92; wy += 12) {
        for (var wx = b.left + 5; wx < b.right - 6; wx += 9) {
          final key = (i * 131 + (wy - b.top).round() * 7 + (wx - b.left).round() * 3) % 97;
          if (key % 5 != 0) continue;
          lit.color = (key % 7 == 0 ? const Color(0xFF8DB4E6) : const Color(0xFFE8C27A)).withValues(alpha: 0.5);
          c.drawRect(Rect.fromLTWH(wx, wy, 4, 6), lit);
        }
      }
    }
  }

  layer(_skyline(size, 71, h * 0.74, h * 0.1, h * 0.26), const Color(0xFF2E2756));
  layer(_skyline(size, 81, h * 0.82, h * 0.08, h * 0.26), const Color(0xFF141029), windows: true);
  // The street.
  c.drawRect(Rect.fromLTWH(0, h * 0.93, w, h * 0.07), Paint()..color = const Color(0xFF0B0819));
}

final _carLight = Paint()
  ..strokeWidth = 2.4
  ..strokeCap = StrokeCap.round;

void _cityMotion(Canvas c, Size size, double t) {
  final w = size.width, h = size.height;
  // Stars above the skyline.
  for (var i = 0; i < 40; i++) {
    final sd = _seeds[i + 20];
    final a = 0.2 + 0.6 * (0.5 + 0.5 * math.sin(t * (0.7 + sd[2]) + sd[3] * 9));
    _glowDot(sd[0] * w, sd[1] * h * 0.4, (0.6 + sd[2]) * 2.2, Color.fromRGBO(255, 255, 255, a));
  }
  _stamps.draw(c, _dot);
  // Car lights along the street.
  for (var i = 0; i < 8; i++) {
    final sd = _seeds[i + 110];
    final dir = i.isEven ? 1 : -1;
    final x = (sd[0] * w + dir * t * (40 + sd[2] * 40)) % (w + 40) - 20;
    final y = h * (0.945 + (i.isEven ? 0 : 0.02));
    final color = dir > 0 ? const Color(0xFFFF5A5A) : const Color(0xFFFFF4D6);
    c.drawLine(Offset(x, y), Offset(x - dir * 14, y), _carLight..color = color.withValues(alpha: 0.8));
  }
}
