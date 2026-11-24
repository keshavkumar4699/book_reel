import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/models/book.dart';
import 'haptics.dart';
import 'kit.dart';
import 'theme.dart';
import '../l10n/l10n.dart';

/// Goal ring (like activity rings) showing today's progress.
class GoalRing extends StatelessWidget {
  const GoalRing({super.key, required this.progress, required this.label, this.size = 120, this.sublabel});

  final double progress;
  final String label;
  final String? sublabel;
  final double size;

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    // Blue on its way, green once met.
    final met = progress >= 1;
    return Semantics(
      label: met ? tr('Daily goal {goal}, done', {'goal': '$label${sublabel == null ? '' : ' $sublabel'}'}) : tr('Daily goal {goal}', {'goal': '$label${sublabel == null ? '' : ' $sublabel'}'}),
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(progress: progress, track: met ? kit.growthSoft : kit.activitySoft, color: met ? kit.growth : kit.activity),
          // Large text shrinks to fit inside the ring rather than spill out.
          child: Padding(
            padding: EdgeInsets.all(size * 0.16),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (met) Icon(Icons.check_rounded, size: size * 0.16, color: kit.growth),
                  Text(label, style: kit.title.copyWith(fontSize: size * 0.17)),
                  if (sublabel != null) Text(sublabel!, style: kit.caption.copyWith(fontSize: 12.5)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.track, required this.color});
  final double progress;
  final Color track;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 12.0;
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect.deflate(stroke / 2), 0, math.pi * 2, false, paint..color = track);
    if (progress > 0) {
      canvas.drawArc(rect.deflate(stroke / 2), -math.pi / 2, math.pi * 2 * progress.clamp(0, 1), false,
          paint..color = color);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress || old.color != color || old.track != track;
}

/// Streak flame with count. A broken streak is shown in a muted tone, never red.
class StreakBadge extends StatelessWidget {
  const StreakBadge({super.key, required this.days, this.weekly = false});
  final int days;
  final bool weekly;

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    final count = weekly ? trn(days, '{n} week', '{n} weeks') : trn(days, '{n} day', '{n} days');
    return Semantics(
      label: tr('{count} streak', {'count': count}),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.local_fire_department_rounded, color: days > 0 ? ember : kit.inkSoft, size: 26),
        const SizedBox(width: 4),
        Text(count, style: kit.heading),
      ]),
    );
  }
}

final Map<String, bool> _exists = {};

/// Whether [path] exists, checked once per path (covers are written once and
/// never move, so build methods need not hit the disk every frame).
bool fileExists(String path) => _exists[path] ??= File(path).existsSync();

/// Book cover: the EPUB cover image when available, otherwise a typographic
/// cover generated from the title.
class BookCover extends StatelessWidget {
  const BookCover({super.key, required this.book, this.width = 110, this.radius = 8});
  final BookMeta book;
  final double width;
  final double radius;

  static const _palette = [
    Color(0xFF7A4E2D), Color(0xFF2F5D62), Color(0xFF5B3F6E), Color(0xFF8C3B3B), Color(0xFF3D5A80), Color(0xFF4F6D3A),
  ];

  @override
  Widget build(BuildContext context) {
    final height = width * 1.5;
    final path = book.coverPath;
    Widget child;
    if (path != null && fileExists(path)) {
      // Decoded at the size it is shown, not the cover's full resolution.
      child = Image.file(File(path),
          width: width, height: height, fit: BoxFit.cover, cacheWidth: (width * MediaQuery.devicePixelRatioOf(context)).round());
    } else {
      final color = _palette[book.title.hashCode.abs() % _palette.length];
      // Drawn like cover art, at a fixed size: the phone's text size doesn't
      // apply (the cover's label reads the title to screen readers).
      child = MediaQuery.withNoTextScaling(child: Container(
        width: width,
        height: height,
        color: color,
        padding: EdgeInsets.all(width * 0.1),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(book.title,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontFamily: 'Literata', color: Colors.white, fontSize: width * 0.13, fontWeight: FontWeight.w600, height: 1.15)),
          const Spacer(),
          Text(book.author,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white70, fontSize: width * 0.09)),
        ]),
      ));
    }
    return Semantics(
      label: tr('{title} by {author}', {'title': book.title, 'author': book.author}),
      child: ClipRRect(borderRadius: BorderRadius.circular(radius), child: child),
    );
  }
}

/// A book's cover with how far you've read drawn round it: an outline that
/// runs clockwise from the top centre, in the pink of books while you read
/// and green once the book is finished, over a faint track of the same
/// colour.
class ProgressCover extends StatelessWidget {
  const ProgressCover({super.key, required this.book, this.width = 76, this.progress, this.stroke = 3});
  final BookMeta book;
  final double width;

  /// How far (0–1); the book's own progress if not given.
  final double? progress;
  final double stroke;

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    final p = book.finishedAt != null ? 1.0 : (progress ?? book.progress).clamp(0.0, 1.0);
    final done = p >= 1;
    final gap = stroke + 2.5;
    final color = done ? kit.growth : kit.hue(KitHue.books);
    return Semantics(
      value: done ? tr('finished') : tr('{percent}% read', {'percent': (p * 100).round()}),
      child: CustomPaint(
        foregroundPainter: CoverOutlinePainter(
          progress: p,
          color: color,
          // A thin line needs a firmer track than a ring to read as one outline.
          track: Color.alphaBlend(color.withValues(alpha: 0.2), kit.base),
          stroke: stroke,
          // Concentric with the cover's own rounded corners.
          radius: 8 + gap - stroke / 2,
        ),
        child: Padding(padding: EdgeInsets.all(gap), child: BookCover(book: book, width: width)),
      ),
    );
  }
}

/// A rounded outline filled clockwise from the top centre to [progress].
class CoverOutlinePainter extends CustomPainter {
  CoverOutlinePainter({required this.progress, required this.color, required this.track, required this.stroke, required this.radius});
  final double progress;
  final Color color;
  final Color track;
  final double stroke;
  final double radius;

  /// The outline from the top centre, clockwise and back.
  static Path outline(Rect r, double radius) {
    final c = Radius.circular(radius);
    return Path()
      ..moveTo(r.center.dx, r.top)
      ..lineTo(r.right - radius, r.top)
      ..arcToPoint(Offset(r.right, r.top + radius), radius: c)
      ..lineTo(r.right, r.bottom - radius)
      ..arcToPoint(Offset(r.right - radius, r.bottom), radius: c)
      ..lineTo(r.left + radius, r.bottom)
      ..arcToPoint(Offset(r.left, r.bottom - radius), radius: c)
      ..lineTo(r.left, r.top + radius)
      ..arcToPoint(Offset(r.left + radius, r.top), radius: c)
      ..lineTo(r.center.dx, r.top);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = outline((Offset.zero & size).deflate(stroke / 2), radius);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, paint..color = track);
    if (progress <= 0) return;
    if (progress >= 1) {
      canvas.drawPath(path, paint..color = color);
      return;
    }
    final metric = path.computeMetrics().first;
    canvas.drawPath(metric.extractPath(0, metric.length * progress), paint..color = color);
  }

  @override
  bool shouldRepaint(CoverOutlinePainter old) =>
      old.progress != progress || old.color != color || old.track != track || old.stroke != stroke || old.radius != radius;
}

/// A short celebration: scales in once, with haptics. Collapses to a static
/// icon when the system asks for reduced motion (UX_DESIGN.md §6.4).
class Celebration extends StatefulWidget {
  const Celebration({super.key, this.big = false});
  final bool big;

  @override
  State<Celebration> createState() => _CelebrationState();
}

class _CelebrationState extends State<Celebration> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));

  @override
  void initState() {
    super.initState();
    Haptics.success();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.of(context).disableAnimations) {
        _c.value = 1;
      } else {
        _c.forward();
      }
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.big ? 96.0 : 72.0;
    return ScaleTransition(
      scale: CurvedAnimation(parent: _c, curve: Curves.elasticOut),
      // The goal done is green (a streak milestone keeps its flame).
      child: Icon(widget.big ? Icons.local_fire_department : Icons.check_circle, size: size, color: widget.big ? ember : Kit.of(context).growth),
    );
  }
}
