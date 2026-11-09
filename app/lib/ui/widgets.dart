import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models/book.dart';
import 'theme.dart';

/// Goal ring (like activity rings) showing today's progress.
class GoalRing extends StatelessWidget {
  const GoalRing({super.key, required this.progress, required this.label, this.size = 120, this.sublabel});

  final double progress;
  final String label;
  final String? sublabel;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Daily goal $label${sublabel == null ? '' : ' $sublabel'}',
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(progress: progress, track: scheme.surfaceContainerHighest, color: ember),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(label, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              if (sublabel != null) Text(sublabel!, style: Theme.of(context).textTheme.bodySmall),
            ]),
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

/// Streak flame with count. A broken streak is shown in neutral grey, never red.
class StreakBadge extends StatelessWidget {
  const StreakBadge({super.key, required this.days, this.weekly = false});
  final int days;
  final bool weekly;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final unit = weekly ? (days == 1 ? 'week' : 'weeks') : (days == 1 ? 'day' : 'days');
    return Semantics(
      label: '$days $unit streak',
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.local_fire_department, color: days > 0 ? ember : muted),
        const SizedBox(width: 4),
        Text('$days $unit', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// Book cover: the EPUB cover image when available, otherwise a typographic
/// cover generated from the title.
class BookCover extends StatelessWidget {
  const BookCover({super.key, required this.book, this.width = 110});
  final BookMeta book;
  final double width;

  static const _palette = [
    Color(0xFF7A4E2D), Color(0xFF2F5D62), Color(0xFF5B3F6E), Color(0xFF8C3B3B), Color(0xFF3D5A80), Color(0xFF4F6D3A),
  ];

  @override
  Widget build(BuildContext context) {
    final height = width * 1.5;
    final path = book.coverPath;
    Widget child;
    if (path != null && File(path).existsSync()) {
      child = Image.file(File(path), width: width, height: height, fit: BoxFit.cover);
    } else {
      final color = _palette[book.title.hashCode.abs() % _palette.length];
      child = Container(
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
      );
    }
    return Semantics(
      label: '${book.title} by ${book.author}',
      child: ClipRRect(borderRadius: BorderRadius.circular(8), child: child),
    );
  }
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
    HapticFeedback.mediumImpact();
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
      child: Icon(widget.big ? Icons.local_fire_department : Icons.check_circle, size: size, color: ember),
    );
  }
}
