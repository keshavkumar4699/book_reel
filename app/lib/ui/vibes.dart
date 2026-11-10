import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/settings.dart';
import 'theme.dart';

/// Visual style for each calm "study vibe" (text sits on a tinted glass card).
class VibeStyle {
  const VibeStyle({
    required this.label,
    required this.emoji,
    required this.tagline,
    required this.accent,
    this.dark = true,
  });

  final String label;
  final String emoji;
  final String tagline;
  final Color accent;
  final bool dark;

  Color get text => dark ? const Color(0xFFFFF8EE) : const Color(0xFF1F1D1A);
  Color get muted => dark ? const Color(0xB3FFF8EE) : const Color(0xFF6E685E);
  Color get glass => dark ? const Color(0x9E10131A) : const Color(0xE6FFFDF8);
  Color get glassBorder => dark ? const Color(0x24FFFFFF) : const Color(0x14000000);
}

const vibeStyles = <Vibe, VibeStyle>{
  Vibe.forest: VibeStyle(label: 'Forest', emoji: '🌲', tagline: 'Misty pines at dawn', accent: Color(0xFFF2C46D)),
  Vibe.cafe: VibeStyle(label: 'Café', emoji: '☕', tagline: 'Rainy evening, warm cup', accent: Color(0xFFFFB86B)),
  Vibe.rain: VibeStyle(label: 'Rain', emoji: '🌧️', tagline: 'City lights through rain', accent: Color(0xFF8FC1FF)),
  Vibe.ocean: VibeStyle(label: 'Ocean', emoji: '🌅', tagline: 'Slow waves at sunset', accent: Color(0xFFFFB38A)),
  Vibe.night: VibeStyle(label: 'Night', emoji: '🌙', tagline: 'Stars over the mountains', accent: Color(0xFFC9B8FF)),
  Vibe.paper: VibeStyle(label: 'Paper', emoji: '📄', tagline: 'Plain and focused', accent: ember, dark: false),
};

/// Reading-surface colours used on top of a scene.
ReadingTheme readingThemeForVibe(Vibe vibe, ReadingTheme paper) {
  if (vibe == Vibe.paper) return paper;
  final s = vibeStyles[vibe]!;
  return ReadingTheme(
    background: const Color(0x00000000),
    text: s.text,
    muted: s.muted,
    keyPoint: s.accent.withValues(alpha: 0.28),
    hardWordUnderline: s.accent,
    highlights: const [Color(0x66FFC66B), Color(0x6673D69A), Color(0x666FA8FF), Color(0x66FF8FB8)],
    isDark: true,
    glass: s.glass,
  );
}

/// A calm, slowly animated scene. Paints in its own layer so text above it
/// never repaints with it. Static when animations are off or reduced.
class VibeBackground extends StatefulWidget {
  const VibeBackground({super.key, required this.vibe, this.animate = true, this.pager, this.paperColor});

  final Vibe vibe;
  final bool animate;

  /// When given, layers drift sideways as pages scroll (parallax).
  final PageController? pager;
  final Color? paperColor;

  @override
  State<VibeBackground> createState() => _VibeBackgroundState();
}

class _VibeBackgroundState extends State<VibeBackground> with SingleTickerProviderStateMixin {
  // One slow loop; scenes derive all motion from elapsed seconds.
  late final AnimationController _clock = AnimationController(vsync: this, duration: const Duration(seconds: 240));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(VibeBackground old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final run = widget.animate && !reduce && widget.vibe != Vibe.paper;
    if (run && !_clock.isAnimating) {
      _clock.repeat();
    } else if (!run && _clock.isAnimating) {
      _clock.stop();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  double _scroll() {
    final p = widget.pager;
    if (p == null || !p.hasClients || !p.position.haveDimensions) return 0;
    return p.page ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.vibe == Vibe.paper) {
      return ColoredBox(color: widget.paperColor ?? const Color(0xFFFBF8F1), child: const SizedBox.expand());
    }
    final repaint = widget.pager == null ? _clock : Listenable.merge([_clock, widget.pager]);
    return RepaintBoundary(
      child: CustomPaint(
        painter: ScenePainter(widget.vibe, () => _clock.value * 240, _scroll, repaint),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// Paints one scene. [seconds] and [scroll] are read at paint time.
class ScenePainter extends CustomPainter {
  ScenePainter(this.vibe, this.seconds, this.scroll, Listenable? repaint) : super(repaint: repaint);

  final Vibe vibe;
  final double Function() seconds;
  final double Function() scroll;

  @override
  void paint(Canvas canvas, Size size) {
    final t = seconds();
    final s = scroll();
    switch (vibe) {
      case Vibe.forest:
        _forest(canvas, size, t, s);
      case Vibe.cafe:
        _cafe(canvas, size, t, s);
      case Vibe.rain:
        _rain(canvas, size, t, s);
      case Vibe.ocean:
        _ocean(canvas, size, t, s);
      case Vibe.night:
        _night(canvas, size, t, s);
      case Vibe.paper:
        canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFFBF8F1));
    }
  }

  @override
  bool shouldRepaint(ScenePainter old) => old.vibe != vibe;
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

/// Draws [path] twice so a horizontally drifting layer wraps seamlessly.
void _wrapped(Canvas c, Path path, double width, double dx, Paint paint) {
  final x = -(dx % width);
  c.save();
  c.translate(x, 0);
  c.drawPath(path, paint);
  c.translate(width, 0);
  c.drawPath(path, paint);
  c.restore();
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
// Scenes

void _forest(Canvas c, Size size, double t, double scroll) {
  final w = size.width, h = size.height;
  _gradient(c, size, const [Color(0xFFF6D8B0), Color(0xFFD7E3C4), Color(0xFF7E9C84), Color(0xFF2C4537)], const [0, 0.38, 0.66, 1]);
  _glow(c, Offset(w * 0.72, h * 0.26), w * 0.55, const Color(0xCCFFF1D2));
  const layers = [
    (Color(0xFFA9C2A8), 0.50, 0.10, 0.20, 0.15),
    (Color(0xFF7FA287), 0.60, 0.14, 0.26, 0.35),
    (Color(0xFF527660), 0.73, 0.18, 0.32, 0.65),
    (Color(0xFF2E4A3A), 0.88, 0.22, 0.40, 1.0),
  ];
  for (var i = 0; i < layers.length; i++) {
    final (color, base, minH, maxH, speed) = layers[i];
    final path = _cached('forest$i-${w.round()}x${h.round()}',
        () => _pineRidge(size, 11 + i, h * base, h * minH, h * maxH, w * (0.16 - i * 0.02)));
    _wrapped(c, path, w, scroll * 22 * speed + t * 1.5 * speed, Paint()..color = color);
    if (i < 2) {
      // Morning mist between the far ridges.
      final y = h * (base + 0.02);
      c.drawRect(
        Rect.fromLTWH(0, y - h * 0.06, w, h * 0.12),
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x00FFFFFF), Color(0x55FFFFFF), Color(0x00FFFFFF)],
          ).createShader(Rect.fromLTWH(0, y - h * 0.06, w, h * 0.12)),
      );
    }
  }
  // Fireflies drifting up through the trees.
  final fly = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
  for (var i = 0; i < 26; i++) {
    final sd = _seeds[i];
    final rise = (t * (6 + sd[2] * 8) + sd[1] * h * 0.5) % (h * 0.5);
    final x = sd[0] * w + math.sin(t * 0.4 + sd[3] * 6) * 18;
    final y = h * 0.98 - rise;
    final a = 0.25 + 0.75 * (0.5 + 0.5 * math.sin(t * 1.6 + sd[3] * 10));
    c.drawCircle(Offset(x, y), 2.2 + sd[2] * 1.8, fly..color = Color.fromRGBO(255, 233, 168, a * 0.9));
  }
}

void _cafe(Canvas c, Size size, double t, double scroll) {
  final w = size.width, h = size.height;
  _gradient(c, size, const [Color(0xFF2A1C15), Color(0xFF3F2A20), Color(0xFF4E3426)], const [0, 0.6, 1]);
  // Window with a rainy city outside.
  final win = RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.08, h * 0.12, w * 0.84, h * 0.46), const Radius.circular(18));
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
    final x = win.left + ((sd[0] * win.width + scroll * 6 * (0.3 + sd[2])) % win.width);
    final y = win.top + win.height * (0.45 + sd[1] * 0.5);
    c.drawCircle(Offset(x, y), 8 + sd[2] * 16, bokeh..color = warm[i % warm.length].withValues(alpha: 0.35));
  }
  final rainPaint = Paint()
    ..color = const Color(0x40FFFFFF)
    ..strokeWidth = 1.2;
  for (var i = 0; i < 60; i++) {
    final sd = _seeds[i + 50];
    final y = win.top + ((sd[1] * win.height + t * (160 + sd[2] * 120)) % win.height);
    final x = win.left + sd[0] * win.width;
    c.drawLine(Offset(x, y), Offset(x - 3, y + 12 + sd[3] * 8), rainPaint);
  }
  c.restore();
  final frame = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 10
    ..color = const Color(0xFF1C130E);
  c.drawRRect(win, frame);
  c.drawLine(Offset(win.center.dx, win.top), Offset(win.center.dx, win.bottom), frame..strokeWidth = 6);
  // Pendant lights with a soft flicker.
  for (var i = 0; i < 3; i++) {
    final x = w * (0.2 + i * 0.3);
    final y = h * (0.07 + (i.isEven ? 0.02 : 0));
    c.drawLine(Offset(x, 0), Offset(x, y), Paint()
      ..color = const Color(0xFF120C08)
      ..strokeWidth = 2);
    final flicker = 0.85 + 0.15 * math.sin(t * 2.3 + i * 2);
    _glow(c, Offset(x, y + 8), 90, Color.fromRGBO(255, 205, 140, 0.32 * flicker));
    c.drawCircle(Offset(x, y + 8), 7, Paint()..color = const Color(0xFFFFE3AE));
  }
  // Table and a steaming cup.
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
      Paint()..color = const Color(0xFFE9DDCC));
  c.drawCircle(Offset(cup.dx + 28, cup.dy - 22), 9, Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 5
    ..color = const Color(0xFFE9DDCC));
  final steam = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3
    ..strokeCap = StrokeCap.round;
  for (var i = 0; i < 3; i++) {
    final phase = (t * 0.35 + i / 3) % 1.0;
    final base = Offset(cup.dx - 12 + i * 12, cup.dy - 46);
    final path = Path()..moveTo(base.dx, base.dy);
    for (var k = 1; k <= 6; k++) {
      final y = base.dy - k * 9 - phase * 20;
      path.lineTo(base.dx + math.sin(k * 0.9 + t * 1.2 + i) * 6, y);
    }
    c.drawPath(path, steam..color = Color.fromRGBO(255, 255, 255, 0.28 * (1 - phase)));
  }
}

void _rain(Canvas c, Size size, double t, double scroll) {
  final w = size.width, h = size.height;
  _gradient(c, size, const [Color(0xFF0D1626), Color(0xFF182A42), Color(0xFF22384F)], const [0, 0.55, 1]);
  final bokeh = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
  const colors = [Color(0xFFFFC27A), Color(0xFF7FB2FF), Color(0xFFFF8FA3), Color(0xFFFFE6A8)];
  for (var i = 0; i < 26; i++) {
    final sd = _seeds[i + 70];
    final x = (sd[0] * w + scroll * 10 * (0.2 + sd[2])) % w;
    final y = h * (0.35 + sd[1] * 0.6);
    final a = 0.18 + 0.12 * math.sin(t * 0.5 + sd[3] * 8);
    c.drawCircle(Offset(x, y), 10 + sd[2] * 24, bokeh..color = colors[i % colors.length].withValues(alpha: a));
  }
  final streak = Paint()
    ..color = const Color(0x30BFD6F2)
    ..strokeWidth = 1.1;
  for (var i = 0; i < 110; i++) {
    final sd = _seeds[i % 160];
    final speed = 260 + sd[2] * 220;
    final y = ((sd[1] * h + t * speed + i * 37) % (h + 40)) - 20;
    final x = (sd[0] * w + i * 13) % w;
    c.drawLine(Offset(x, y), Offset(x - 4, y + 16 + sd[3] * 10), streak);
  }
  // Droplets sliding down the glass.
  for (var i = 0; i < 22; i++) {
    final sd = _seeds[i + 100];
    final y = (sd[1] * h + t * (3 + sd[2] * 6)) % h;
    final o = Offset(sd[0] * w, y);
    final r = 2.5 + sd[3] * 3.5;
    c.drawCircle(o, r, Paint()..color = const Color(0x22D8E8FF));
    c.drawCircle(o.translate(-r * 0.3, -r * 0.3), r * 0.35, Paint()..color = const Color(0x55FFFFFF));
  }
}

void _ocean(Canvas c, Size size, double t, double scroll) {
  final w = size.width, h = size.height;
  final horizon = h * 0.56;
  _gradient(c, Size(w, horizon), const [Color(0xFF3A3A6A), Color(0xFFA25E86), Color(0xFFF1A26C)], const [0, 0.55, 1]);
  // Soft clouds.
  final cloud = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
  for (var i = 0; i < 6; i++) {
    final sd = _seeds[i + 120];
    final x = (sd[0] * w + t * (2 + sd[2] * 3) + scroll * 8) % (w + 200) - 100;
    c.drawOval(Rect.fromCenter(center: Offset(x, horizon * (0.25 + sd[1] * 0.5)), width: 160 + sd[3] * 120, height: 26 + sd[2] * 18),
        cloud..color = const Color(0x40FFD3C2));
  }
  final sun = Offset(w * 0.5, horizon);
  _glow(c, sun, w * 0.6, const Color(0x99FFD39A));
  c.save();
  c.clipRect(Rect.fromLTWH(0, 0, w, horizon));
  c.drawCircle(sun, w * 0.13, Paint()..color = const Color(0xFFFFD9A0));
  c.restore();
  final sea = Rect.fromLTWH(0, horizon, w, h - horizon);
  c.drawRect(
    sea,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF7A5E8E), Color(0xFF34406A), Color(0xFF18213D)],
      ).createShader(sea),
  );
  // Shimmer on the sun's path.
  final shimmer = Paint()..strokeWidth = 2;
  for (var i = 0; i < 40; i++) {
    final sd = _seeds[i];
    final y = horizon + 6 + sd[1] * (h - horizon) * 0.55;
    final spread = 18 + (y - horizon) * 0.5;
    final x = sun.dx + (sd[0] - 0.5) * spread * 2 + math.sin(t * 0.8 + sd[3] * 6) * 6;
    final a = 0.15 + 0.45 * (0.5 + 0.5 * math.sin(t * 2 + sd[2] * 9));
    shimmer.color = Color.fromRGBO(255, 220, 170, a);
    c.drawLine(Offset(x - 8 - sd[2] * 10, y), Offset(x + 8 + sd[2] * 10, y), shimmer);
  }
  // Gentle waves in the foreground.
  for (var layer = 0; layer < 3; layer++) {
    final baseY = h * (0.8 + layer * 0.07);
    final path = Path()..moveTo(0, h);
    for (var x = 0.0; x <= w + 10; x += 10) {
      final y = baseY + math.sin(x / (60 + layer * 20) + t * (0.5 + layer * 0.2) + scroll * 0.6) * (5 + layer * 3);
      path.lineTo(x, y);
    }
    path.lineTo(w, h);
    path.close();
    c.drawPath(path, Paint()..color = Color.fromRGBO(16, 24, 48, 0.35 + layer * 0.2));
  }
}

void _night(Canvas c, Size size, double t, double scroll) {
  final w = size.width, h = size.height;
  _gradient(c, size, const [Color(0xFF080C20), Color(0xFF161D40), Color(0xFF2B2B5A)], const [0, 0.6, 1]);
  for (var i = 0; i < 130; i++) {
    final sd = _seeds[i % 160];
    final x = ((sd[0] + i * 0.0137) % 1) * w;
    final y = ((sd[1] + i * 0.0071) % 1) * h * 0.7;
    final a = 0.25 + 0.75 * (0.5 + 0.5 * math.sin(t * (0.8 + sd[2] * 1.6) + sd[3] * 12));
    c.drawCircle(Offset(x, y), 0.6 + sd[2] * 1.3, Paint()..color = Color.fromRGBO(255, 255, 255, a));
  }
  final moon = Offset(w * 0.78, h * 0.17);
  _glow(c, moon, 120, const Color(0x55E8E6FF));
  c.drawCircle(moon, 26, Paint()..color = const Color(0xFFF4F1E0));
  c.drawCircle(moon.translate(9, -5), 23, Paint()..color = const Color(0xFF12183A).withValues(alpha: 0.9));
  // An occasional shooting star (every ~16 s).
  final cycle = t % 16;
  if (cycle < 1.2) {
    final p = cycle / 1.2;
    final start = Offset(w * 0.15, h * 0.12);
    final head = start + Offset(w * 0.5 * p, h * 0.12 * p);
    c.drawLine(head - Offset(w * 0.08, h * 0.02), head, Paint()
      ..shader = LinearGradient(colors: [const Color(0x00FFFFFF), Color.fromRGBO(255, 255, 255, 0.9 * (1 - p))])
          .createShader(Rect.fromPoints(head - Offset(w * 0.08, h * 0.02), head))
      ..strokeWidth = 2);
  }
  const ridges = [(Color(0xFF2A2F5C), 0.66, 0.16, 0.2), (Color(0xFF1C2046), 0.76, 0.14, 0.5), (Color(0xFF10132E), 0.88, 0.12, 1.0)];
  for (var i = 0; i < ridges.length; i++) {
    final (color, base, amp, speed) = ridges[i];
    final path = _cached('night$i-${w.round()}x${h.round()}', () => _mountains(size, 31 + i, h * base, h * amp, 5 + i * 2));
    _wrapped(c, path, w, scroll * 18 * speed, Paint()..color = color);
    if (i == 0) {
      final y = h * (base + 0.03);
      c.drawRect(
        Rect.fromLTWH(0, y - h * 0.05, w, h * 0.1),
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x00B8B8FF), Color(0x22B8B8FF), Color(0x00B8B8FF)],
          ).createShader(Rect.fromLTWH(0, y - h * 0.05, w, h * 0.1)),
      );
    }
  }
}

/// Horizontal row of scene thumbnails (static) for picking a vibe.
class VibePickerRow extends StatelessWidget {
  const VibePickerRow({super.key, required this.selected, required this.onSelected, this.height = 132});

  final Vibe selected;
  final ValueChanged<Vibe> onSelected;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: height + 28,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: Vibe.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final v = Vibe.values[i];
          final style = vibeStyles[v]!;
          final isSelected = v == selected;
          return Semantics(
            button: true,
            selected: isSelected,
            label: '${style.label} vibe: ${style.tagline}',
            child: GestureDetector(
              onTap: () => onSelected(v),
              child: Column(children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: height * 0.62,
                  height: height,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: isSelected ? style.accent : Colors.transparent, width: 3),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Stack(fit: StackFit.expand, children: [
                      VibeBackground(vibe: v, animate: false),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(style.emoji, style: const TextStyle(fontSize: 22)),
                        ),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 4),
                Text(style.label,
                    style: TextStyle(fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500, color: scheme.onSurface)),
              ]),
            ),
          );
        },
      ),
    );
  }
}
