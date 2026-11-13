import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../ui/kit.dart';

/// Opens the crop step for a picked photo. Returns a square PNG of
/// [outputSize] pixels (what the circle shows), or null when cancelled.
Future<Uint8List?> showAvatarCropper(BuildContext context, Uint8List image, {int outputSize = 512}) =>
    Navigator.of(context).push<Uint8List>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => AvatarCropper(image: image, outputSize: outputSize),
    ));

/// Move and scale a photo inside a circle (Cloro plan §11): the picture fills
/// the circle (no letterboxing), centred on the part you choose.
class AvatarCropper extends StatefulWidget {
  const AvatarCropper({super.key, required this.image, this.outputSize = 512});

  final Uint8List image;
  final int outputSize;

  @override
  State<AvatarCropper> createState() => _AvatarCropperState();
}

class _AvatarCropperState extends State<AvatarCropper> {
  final _square = GlobalKey();
  bool _saving = false;

  Future<void> _use() async {
    setState(() => _saving = true);
    final boundary = _square.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: widget.outputSize / boundary.size.width);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (mounted) Navigator.of(context).pop(png!.buffer.asUint8List());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
            child: Row(children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel', style: TextStyle(color: Colors.white, fontSize: 16)),
              ),
              const Expanded(
                child: Text('Move and scale', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              KitButton(label: _saving ? 'Saving…' : 'Use photo', compact: true, onPressed: _saving ? null : _use),
            ]),
          ),
          Expanded(
            child: LayoutBuilder(builder: (context, c) {
              final side = (c.biggest.shortestSide - 32).clamp(120.0, 520.0);
              return Center(
                child: SizedBox.square(
                  dimension: side,
                  child: Stack(fit: StackFit.expand, children: [
                    // What is inside this square is what's kept.
                    RepaintBoundary(
                      key: _square,
                      child: ClipRect(
                        child: InteractiveViewer(
                          minScale: 1,
                          maxScale: 5,
                          child: Image.memory(widget.image, fit: BoxFit.cover, width: side, height: side, gaplessPlayback: true),
                        ),
                      ),
                    ),
                    // The circle your picture will show in.
                    IgnorePointer(child: CustomPaint(painter: _CircleMask())),
                  ]),
                ),
              );
            }),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 20),
            child: Text('Pinch to zoom, drag to move.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
          ),
        ]),
      ),
    );
  }
}

/// Darkens the corners outside the circle and draws its edge.
class _CircleMask extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final circle = Path()..addOval(rect.deflate(1));
    final outside = Path.combine(PathOperation.difference, Path()..addRect(rect), circle);
    canvas.drawPath(outside, Paint()..color = const Color(0x99000000));
    canvas.drawPath(
        circle,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xE6FFFFFF));
  }

  @override
  bool shouldRepaint(_CircleMask old) => false;
}
