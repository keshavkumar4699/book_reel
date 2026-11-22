part of 'scenes.dart';

// --------------------------------------------------------------------------
// Study scenes: a girl reading or studying, each in her own place, painted
// like the other scenes (a still base, and light motion that loops for as
// long as the scene is on screen). Text sits over the middle of the screen,
// so the people and their things are low in the picture and the windows high.

// Colours shared by the girl in every scene.
const _skin = Color(0xFFE9B99A);
const _skinShade = Color(0xFFC98F72);

/// A gentle to-and-fro of [period] seconds, -1 to 1.
double _sway(double t, double period, [double phase = 0]) => math.sin((t / period + phase) * 2 * math.pi);

/// Steam curling up from a cup's rim at [rim], [width] across.
void _steamFrom(Canvas c, Offset rim, double width, double t, {double alpha = 0.3}) {
  for (var i = 0; i < 3; i++) {
    final phase = (t * 0.32 + i / 3) % 1.0;
    final base = Offset(rim.dx - width * 0.3 + i * width * 0.3, rim.dy - 4);
    final path = Path()..moveTo(base.dx, base.dy);
    for (var k = 1; k <= 6; k++) {
      path.lineTo(base.dx + math.sin(k * 0.9 + t * 1.1 + i) * width * 0.12, base.dy - k * width * 0.2 - phase * width * 0.45);
    }
    c.drawPath(path, _steam..color = Color.fromRGBO(255, 255, 255, alpha * (1 - phase)));
  }
}

/// Rain running down a window pane, clipped to [pane].
void _rainOn(Canvas c, Rect pane, double t, {int count = 50, int seed = 20}) {
  c.save();
  c.clipRect(pane);
  _lines(c, count, (i, out, at) {
    final sd = _seeds[(i + seed) % 160];
    final y = pane.top + ((sd[1] * pane.height + t * (150 + sd[2] * 110)) % pane.height);
    final x = pane.left + sd[0] * pane.width;
    out[at] = x;
    out[at + 1] = y;
    out[at + 2] = x - 2.5;
    out[at + 3] = y + 10 + sd[3] * 8;
  }, _cafeRain);
  c.restore();
}

/// A mug at [bottom] (the middle of its base), [size] across.
void _mug(Canvas c, Offset bottom, double size, Color colour) {
  final body = RRect.fromRectAndRadius(Rect.fromLTWH(bottom.dx - size / 2, bottom.dy - size * 0.9, size, size * 0.9), Radius.circular(size * 0.18));
  c.drawRRect(body, Paint()..color = colour);
  c.drawCircle(
      Offset(bottom.dx + size * 0.58, bottom.dy - size * 0.5),
      size * 0.2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size * 0.11
        ..color = colour);
  c.drawOval(Rect.fromCenter(center: Offset(bottom.dx, bottom.dy - size * 0.9), width: size, height: size * 0.22), Paint()..color = const Color(0xFF4A2C1D));
}

/// A stack of books lying flat, from [bottom] (its left end) up.
void _bookStack(Canvas c, Offset bottom, double width, List<Color> covers) {
  var y = bottom.dy;
  for (final (i, cover) in covers.indexed) {
    final bw = width * (1 - (i % 3) * 0.08);
    final x = bottom.dx + (i.isEven ? 0 : width * 0.05);
    final r = Rect.fromLTWH(x, y - width * 0.16, bw, width * 0.16);
    c.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(2)), Paint()..color = cover);
    c.drawRect(Rect.fromLTWH(r.right - 3, r.top + 2, 2, r.height - 4), Paint()..color = const Color(0x66FFFFFF));
    y -= width * 0.16;
  }
}

/// Leaves of a potted plant fanning out from [root].
void _plant(Canvas c, Offset root, double size, Color leaf, {double sway = 0}) {
  final paint = Paint()..color = leaf;
  for (var i = 0; i < 7; i++) {
    final a = -math.pi / 2 + (i - 3) * 0.32 + sway * 0.05;
    final len = size * (0.75 + 0.25 * math.cos(i * 1.7));
    final tip = root + Offset(math.cos(a), math.sin(a)) * len;
    final mid = root + Offset(math.cos(a), math.sin(a)) * len * 0.55;
    final n = Offset(-math.sin(a), math.cos(a)) * size * 0.16;
    final path = Path()
      ..moveTo(root.dx, root.dy)
      ..quadraticBezierTo(mid.dx + n.dx, mid.dy + n.dy, tip.dx, tip.dy)
      ..quadraticBezierTo(mid.dx - n.dx, mid.dy - n.dy, root.dx, root.dy);
    c.drawPath(path, paint);
  }
}

// --------------------------------------------------------------------------
// Night desk: studying at a desk by a tall window, rain on the glass, the
// city lit up beyond it and a warm lamp.

Rect _nightDeskWindow(Size s) => Rect.fromLTRB(s.width * 0.08, s.height * 0.07, s.width * 0.92, s.height * 0.55);
double _nightDeskTop(Size s) => s.height * 0.745;
Offset _nightDeskLamp(Size s) => Offset(s.width * 0.75, s.height * 0.615);

void _studyNightBase(Canvas c, Size size) {
  final w = size.width, h = size.height;
  _gradient(c, size, const [Color(0xFF1A1630), Color(0xFF231C3A), Color(0xFF2A2042)], const [0, 0.55, 1]);
  final win = _nightDeskWindow(size);
  c.save();
  c.clipRect(win);
  c.drawRect(
    win,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF0A1230), Color(0xFF17285A), Color(0xFF34447A)],
        stops: [0, 0.65, 1],
      ).createShader(win),
  );
  // The moon, and a few stars.
  final moon = Offset(w * 0.73, h * 0.15);
  _glow(c, moon, w * 0.2, const Color(0x40FFF0C8));
  c.drawCircle(moon, w * 0.04, Paint()..color = const Color(0xFFFFF3D2));
  for (var i = 0; i < 16; i++) {
    final sd = _seeds[i + 5];
    c.drawCircle(Offset(win.left + sd[0] * win.width, win.top + sd[1] * win.height * 0.35), 0.8 + sd[2], Paint()..color = const Color(0x99FFFFFF));
  }
  // The city: far blocks, then near ones, their windows lit.
  for (final (row, colour, top) in [(0, const Color(0xFF1A2550), 0.36), (1, const Color(0xFF0F1736), 0.44)]) {
    var x = win.left - 10;
    var k = row * 40;
    while (x < win.right) {
      final sd = _seeds[k++ % 160];
      final bw = w * (0.08 + sd[0] * 0.1);
      final top0 = h * (top + sd[1] * 0.06);
      final b = Rect.fromLTRB(x, top0, x + bw, win.bottom);
      c.drawRect(b, Paint()..color = colour);
      final lit = Paint();
      for (var gy = b.top + 6; gy < b.bottom - 4; gy += 9) {
        for (var gx = b.left + 4; gx < b.right - 4; gx += 8) {
          final r = _seeds[(gx * 7 + gy * 13).round() % 160][3];
          if (r > (row == 0 ? 0.72 : 0.62)) {
            lit.color = (r > 0.93 ? const Color(0xFF9FC7FF) : const Color(0xFFFFCB7A)).withValues(alpha: row == 0 ? 0.55 : 0.8);
            c.drawRect(Rect.fromLTWH(gx, gy, 3.5, 4.5), lit);
          }
        }
      }
      x += bw + w * 0.01;
    }
  }
  c.restore();
  // Frame, glazing bars and the sill.
  final frame = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 9
    ..color = const Color(0xFF130F22);
  c.drawRect(win, frame);
  c.drawLine(Offset(win.center.dx, win.top), Offset(win.center.dx, win.bottom), frame..strokeWidth = 6);
  c.drawLine(Offset(win.left, h * 0.3), Offset(win.right, h * 0.3), frame);
  c.drawRect(Rect.fromLTRB(w * 0.04, win.bottom, w * 0.96, win.bottom + h * 0.018), Paint()..color = const Color(0xFF3B2E52));
  // A little plant on the sill.
  final pot = Rect.fromLTWH(w * 0.13, win.bottom - h * 0.035, w * 0.08, h * 0.035);
  c.drawRRect(RRect.fromRectAndRadius(pot, const Radius.circular(3)), Paint()..color = const Color(0xFF9A5A44));
  _plant(c, Offset(pot.center.dx, pot.top + 2), w * 0.09, const Color(0xFF2F6B4F));
  // The desk.
  final top = _nightDeskTop(size);
  c.drawRect(Rect.fromLTWH(0, top - h * 0.012, w, h * 0.024), Paint()..color = const Color(0xFF6E4C38));
  c.drawRect(
    Rect.fromLTWH(0, top + h * 0.012, w, h - top),
    Paint()
      ..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF3A271D), Color(0xFF1C120C)])
          .createShader(Rect.fromLTWH(0, top, w, h - top)),
  );
  // Books on the left, the lamp on the right.
  _bookStack(c, Offset(w * 0.06, top - h * 0.01), w * 0.2, const [Color(0xFF8E3B3B), Color(0xFF2F5D7C), Color(0xFFC79A4B), Color(0xFF4E6B45)]);
  final lamp = _nightDeskLamp(size);
  final arm = Paint()
    ..color = const Color(0xFF283131)
    ..strokeWidth = 4
    ..strokeCap = StrokeCap.round;
  final foot = Offset(w * 0.86, top - h * 0.012);
  c.drawOval(Rect.fromCenter(center: foot, width: w * 0.12, height: h * 0.012), Paint()..color = const Color(0xFF283131));
  final elbow = Offset(w * 0.9, h * 0.64);
  c.drawLine(foot, elbow, arm);
  c.drawLine(elbow, lamp + Offset(w * 0.03, -h * 0.012), arm);
  final shade = Path()
    ..moveTo(lamp.dx - w * 0.07, lamp.dy + h * 0.012)
    ..lineTo(lamp.dx + w * 0.05, lamp.dy - h * 0.022)
    ..lineTo(lamp.dx + w * 0.07, lamp.dy - h * 0.006)
    ..lineTo(lamp.dx - w * 0.03, lamp.dy + h * 0.03)
    ..close();
  c.drawPath(shade, Paint()..color = const Color(0xFF2F4A46));
  // An open notebook in the lamplight.
  final page = Path()
    ..moveTo(w * 0.47, top - h * 0.006)
    ..lineTo(w * 0.66, top - h * 0.006)
    ..lineTo(w * 0.63, top - h * 0.018)
    ..lineTo(w * 0.5, top - h * 0.018)
    ..close();
  c.drawPath(page, Paint()..color = const Color(0xFFEFE6D2));
  _mug(c, Offset(w * 0.7, top - h * 0.008), w * 0.06, const Color(0xFFB9C7D6));
}

void _studyNightMotion(Canvas c, Size size, double t) {
  final w = size.width, h = size.height;
  final win = _nightDeskWindow(size);
  _rainOn(c, win.deflate(5), t, count: 70);
  // The lamp: its bulb, its light on the desk and on her, breathing a little.
  final lamp = _nightDeskLamp(size);
  final breathe = 0.9 + 0.1 * _sway(t, 5.5);
  final top = _nightDeskTop(size);
  _glow(c, Offset(w * 0.6, top), w * 0.42, Color.fromRGBO(255, 196, 120, 0.22 * breathe));
  _glow(c, lamp + Offset(-w * 0.01, h * 0.02), w * 0.12, Color.fromRGBO(255, 220, 160, 0.55 * breathe));
  _steamFrom(c, Offset(w * 0.7, top - h * 0.008 - w * 0.054), w * 0.06, t);

  // Her, from behind: a sweater, dark hair in a bun, writing.
  final cx = w * 0.4;
  final shoulders = h * 0.69;
  const hair = Color(0xFF2B1B16), sweater = Color(0xFF3F6F73), sweaterShade = Color(0xFF2E5357);
  final body = Path()
    ..moveTo(cx - w * 0.04, shoulders - h * 0.022)
    ..quadraticBezierTo(cx - w * 0.15, shoulders - h * 0.016, cx - w * 0.17, shoulders + h * 0.03)
    ..lineTo(cx - w * 0.19, h * 0.9)
    ..lineTo(cx + w * 0.19, h * 0.9)
    ..lineTo(cx + w * 0.17, shoulders + h * 0.03)
    ..quadraticBezierTo(cx + w * 0.15, shoulders - h * 0.016, cx + w * 0.04, shoulders - h * 0.022)
    ..close();
  c.drawPath(
    body,
    Paint()
      ..shader = LinearGradient(colors: const [sweaterShade, sweater, Color(0xFF4F8A86)], stops: const [0, 0.55, 1])
          .createShader(Rect.fromLTRB(cx - w * 0.19, shoulders, cx + w * 0.19, h * 0.9)),
  );
  // Her right arm reaching to the page; the pencil moving as she writes.
  final write = _sway(t, 1.6) * w * 0.012;
  final hand = Offset(w * 0.56 + write, top - h * 0.012);
  final sleeve = Path()
    ..moveTo(cx + w * 0.15, shoulders + h * 0.01)
    ..quadraticBezierTo(cx + w * 0.22, top - h * 0.04, hand.dx - w * 0.02, hand.dy - h * 0.004)
    ..lineTo(hand.dx - w * 0.035, hand.dy + h * 0.01)
    ..quadraticBezierTo(cx + w * 0.15, top - h * 0.02, cx + w * 0.11, shoulders + h * 0.05)
    ..close();
  c.drawPath(sleeve, Paint()..color = sweater);
  c.drawOval(Rect.fromCenter(center: hand, width: w * 0.035, height: w * 0.026), Paint()..color = _skin);
  c.drawLine(
      hand + Offset(w * 0.006, -w * 0.004),
      hand + Offset(w * 0.03, -w * 0.035),
      Paint()
        ..color = const Color(0xFFE2B34A)
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round);
  // The chair's back, in front of her.
  final chair = RRect.fromRectAndRadius(Rect.fromLTRB(cx - w * 0.16, h * 0.8, cx + w * 0.16, h * 0.93), const Radius.circular(10));
  c.drawRRect(chair, Paint()..color = const Color(0xFF4A3426));
  c.drawRRect(chair.deflate(5), Paint()..color = const Color(0xFF5A4030));
  // Her head, nodding a little as she reads, hair in a bun.
  final neck = Offset(cx, shoulders - h * 0.02);
  c.save();
  c.translate(neck.dx, neck.dy);
  c.rotate(0.035 * _sway(t, 4.8));
  c.translate(-neck.dx, -neck.dy);
  final head = Offset(cx, shoulders - h * 0.06);
  final r = w * 0.075;
  c.drawRect(Rect.fromCenter(center: neck + Offset(0, -h * 0.008), width: r * 0.6, height: h * 0.025), Paint()..color = _skinShade);
  c.drawOval(Rect.fromCenter(center: head + Offset(-r * 0.98, r * 0.1), width: r * 0.28, height: r * 0.42), Paint()..color = _skin);
  c.drawOval(Rect.fromCenter(center: head + Offset(r * 0.98, r * 0.1), width: r * 0.28, height: r * 0.42), Paint()..color = _skin);
  c.drawCircle(head, r, Paint()..color = hair);
  c.drawCircle(head + Offset(r * 0.1, -r * 1.05), r * 0.55, Paint()..color = hair);
  c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: head + Offset(r * 0.06, -r * 0.62), width: r * 0.7, height: r * 0.16), const Radius.circular(3)),
      Paint()..color = const Color(0xFFD0604A));
  // Lamplight catching her hair on the right.
  c.drawArc(
      Rect.fromCircle(center: head, radius: r * 0.92),
      -0.9,
      1.3,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.12
        ..color = Color.fromRGBO(255, 190, 120, 0.35 * breathe));
  c.restore();
}

// --------------------------------------------------------------------------
// Café reading: a book at a little table by the café window, the street
// going by outside and lamps overhead.

Rect _cafeReadWindow(Size s) => Rect.fromLTRB(s.width * 0.05, s.height * 0.1, s.width * 0.7, s.height * 0.58);
double _cafeReadTable(Size s) => s.height * 0.775;

void _studyCafeBase(Canvas c, Size size) {
  final w = size.width, h = size.height;
  _gradient(c, size, const [Color(0xFF34211A), Color(0xFF4A2E22), Color(0xFF5A3A2A)], const [0, 0.6, 1]);
  final win = _cafeReadWindow(size);
  final glass = RRect.fromRectAndRadius(win, const Radius.circular(6));
  c.save();
  c.clipRRect(glass);
  c.drawRect(
    win,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF1D2552), Color(0xFF4B3C78), Color(0xFFB0687A), Color(0xFFE59A6E)],
        stops: [0, 0.45, 0.72, 0.85],
      ).createShader(win),
  );
  // Across the street: houses, their windows and a lamp post.
  var x = win.left;
  var k = 60;
  while (x < win.right) {
    final sd = _seeds[k++ % 160];
    final bw = w * (0.12 + sd[0] * 0.1);
    final b = Rect.fromLTRB(x, h * (0.3 + sd[1] * 0.08), x + bw, win.bottom);
    c.drawRect(b, Paint()..color = const Color(0xFF241A2E));
    for (var gy = b.top + 10; gy < h * 0.5; gy += 16) {
      for (var gx = b.left + 6; gx < b.right - 10; gx += 14) {
        if (_seeds[(gx + gy).round() % 160][2] > 0.45) {
          c.drawRect(Rect.fromLTWH(gx, gy, 6, 8), Paint()..color = const Color(0xCCFFC27A));
        }
      }
    }
    x += bw + 4;
  }
  c.drawRect(Rect.fromLTRB(win.left, h * 0.5, win.right, win.bottom), Paint()..color = const Color(0xFF1A1420));
  final post = Offset(win.left + win.width * 0.78, h * 0.34);
  c.drawLine(post, Offset(post.dx, h * 0.5), Paint()
    ..color = const Color(0xFF111018)
    ..strokeWidth = 3);
  _glow(c, post, w * 0.08, const Color(0x99FFD58A));
  c.restore();
  final frame = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 8
    ..color = const Color(0xFF22150F);
  c.drawRRect(glass, frame);
  c.drawLine(Offset(win.center.dx, win.top), Offset(win.center.dx, win.bottom), frame..strokeWidth = 5);
  // The café's name, backwards on the glass, and a striped awning edge.
  for (var i = 0; i < 9; i++) {
    c.drawRect(Rect.fromLTWH(win.left + i * win.width / 9, win.top - h * 0.02, win.width / 18, h * 0.02),
        Paint()..color = i.isEven ? const Color(0xFF7A2E2A) : const Color(0xFFE7D6BD));
  }
  // Shelves on the right: cups and a plant.
  for (final y in [h * 0.2, h * 0.34]) {
    c.drawRect(Rect.fromLTWH(w * 0.76, y, w * 0.24, h * 0.008), Paint()..color = const Color(0xFF2A1A12));
    for (var i = 0; i < 3; i++) {
      _mug(c, Offset(w * (0.8 + i * 0.065), y), w * 0.04, [const Color(0xFFE8DCCB), const Color(0xFF8FB0A6), const Color(0xFFD69B6B)][i]);
    }
  }
  // The table: a round top on one leg, a cup and saucer.
  final top = _cafeReadTable(size);
  c.drawLine(Offset(w * 0.42, top), Offset(w * 0.42, h * 0.97), Paint()
    ..color = const Color(0xFF1E1510)
    ..strokeWidth = 7);
  c.drawOval(Rect.fromCenter(center: Offset(w * 0.42, h * 0.97), width: w * 0.24, height: h * 0.014), Paint()..color = const Color(0xFF1E1510));
  c.drawOval(Rect.fromCenter(center: Offset(w * 0.42, top), width: w * 0.62, height: h * 0.04), Paint()..color = const Color(0xFF7B5038));
  c.drawOval(Rect.fromCenter(center: Offset(w * 0.42, top - 2), width: w * 0.6, height: h * 0.034), Paint()..color = const Color(0xFF9A6A4C));
  c.drawOval(Rect.fromCenter(center: Offset(w * 0.25, top - 2), width: w * 0.12, height: h * 0.01), Paint()..color = const Color(0xFFEDE3D3));
  _mug(c, Offset(w * 0.25, top - 3), w * 0.065, const Color(0xFFF1E7D6));
}

void _studyCafeMotion(Canvas c, Size size, double t) {
  final w = size.width, h = size.height;
  final win = _cafeReadWindow(size);
  // The street: car lights going by, both ways.
  c.save();
  c.clipRRect(RRect.fromRectAndRadius(win.deflate(4), const Radius.circular(4)));
  for (var i = 0; i < 4; i++) {
    final leftward = i.isEven;
    final p = ((t / 7.0) + i * 0.29) % 1.0;
    final x = leftward ? win.right + 30 - p * (win.width + 60) : win.left - 30 + p * (win.width + 60);
    final y = h * (leftward ? 0.535 : 0.555);
    _glow(c, Offset(x, y), w * 0.05, leftward ? const Color(0x99FFF1C2) : const Color(0x99FF6B5A));
    _glow(c, Offset(x + (leftward ? 18 : -18), y), w * 0.05, leftward ? const Color(0x99FFF1C2) : const Color(0x99FF6B5A));
  }
  c.restore();
  // Lamps overhead, swaying a little on their cords.
  for (final (i, lx) in [w * 0.2, w * 0.6].indexed) {
    final swing = _sway(t, 6.0 + i, i * 0.3) * w * 0.008;
    final bulb = Offset(lx + swing, h * 0.07);
    c.drawLine(Offset(lx, 0), bulb, Paint()
      ..color = const Color(0xFF120C08)
      ..strokeWidth = 2);
    final cone = Path()
      ..moveTo(bulb.dx - w * 0.06, bulb.dy + h * 0.03)
      ..lineTo(bulb.dx - w * 0.02, bulb.dy)
      ..lineTo(bulb.dx + w * 0.02, bulb.dy)
      ..lineTo(bulb.dx + w * 0.06, bulb.dy + h * 0.03)
      ..close();
    c.drawPath(cone, Paint()..color = const Color(0xFF26413E));
    final flicker = 0.88 + 0.12 * _sway(t, 3.1, i * 0.4);
    _glow(c, bulb + Offset(0, h * 0.035), w * 0.22, Color.fromRGBO(255, 200, 130, 0.3 * flicker));
  }
  final top = _cafeReadTable(size);
  _steamFrom(c, Offset(w * 0.25, top - 3 - w * 0.06), w * 0.065, t);

  // Her, side on, reading at the table: a bob, a mustard jumper.
  const hair = Color(0xFF5A2A1F), jumper = Color(0xFFC98A2B), jumperShade = Color(0xFFA9711F);
  final sx = w * 0.66;
  final shoulder = Offset(sx, h * 0.655);
  // Her back and the chair.
  c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(sx + w * 0.07, h * 0.62, sx + w * 0.11, h * 0.86), const Radius.circular(6)),
      Paint()..color = const Color(0xFF2B1B12));
  // The chair's seat and legs, then her: seated, knees under the table.
  final seat = h * 0.845;
  c.drawRect(Rect.fromLTRB(sx - w * 0.06, seat, sx + w * 0.11, seat + h * 0.012), Paint()..color = const Color(0xFF2B1B12));
  for (final lx in [sx - w * 0.05, sx + w * 0.1]) {
    c.drawLine(Offset(lx, seat), Offset(lx, h * 0.97), Paint()
      ..color = const Color(0xFF2B1B12)
      ..strokeWidth = 3);
  }
  const trousers = Color(0xFF3B4058);
  final legs = Path()
    ..moveTo(sx + w * 0.06, seat - h * 0.03)
    ..lineTo(sx - w * 0.13, seat - h * 0.028)
    ..quadraticBezierTo(sx - w * 0.16, seat - h * 0.02, sx - w * 0.15, seat + h * 0.005)
    ..lineTo(sx - w * 0.13, h * 0.94)
    ..lineTo(sx - w * 0.095, h * 0.94)
    ..lineTo(sx - w * 0.1, seat + h * 0.004)
    ..lineTo(sx + w * 0.06, seat + h * 0.002)
    ..close();
  c.drawPath(legs, Paint()..color = trousers);
  c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(sx - w * 0.16, h * 0.935, sx - w * 0.09, h * 0.952), const Radius.circular(4)),
      Paint()..color = const Color(0xFF1E1A1A));
  final body = Path()
    ..moveTo(shoulder.dx - w * 0.05, shoulder.dy - h * 0.006)
    ..quadraticBezierTo(shoulder.dx + w * 0.06, shoulder.dy - h * 0.012, shoulder.dx + w * 0.08, shoulder.dy + h * 0.04)
    ..quadraticBezierTo(shoulder.dx + w * 0.085, seat - h * 0.06, shoulder.dx + w * 0.07, seat - h * 0.02)
    ..lineTo(shoulder.dx - w * 0.07, seat - h * 0.025)
    ..quadraticBezierTo(shoulder.dx - w * 0.09, shoulder.dy + h * 0.04, shoulder.dx - w * 0.05, shoulder.dy - h * 0.006)
    ..close();
  c.drawPath(body, Paint()..color = jumper);
  // The book, held up in both hands; a page turning now and then.
  final book = Offset(w * 0.48, h * 0.675);
  final open = Path()
    ..moveTo(book.dx, book.dy + h * 0.03)
    ..lineTo(book.dx - w * 0.07, book.dy - h * 0.01)
    ..lineTo(book.dx - w * 0.065, book.dy - h * 0.018)
    ..lineTo(book.dx, book.dy + h * 0.018)
    ..lineTo(book.dx + w * 0.01, book.dy - h * 0.035)
    ..lineTo(book.dx + w * 0.02, book.dy - h * 0.028)
    ..close();
  c.drawPath(open, Paint()..color = const Color(0xFFF3EBDD));
  c.drawLine(book + Offset(0, h * 0.03), book + Offset(-w * 0.07, -h * 0.01), Paint()
    ..color = const Color(0xFF2F5D7C)
    ..strokeWidth = 3);
  final turn = (t % 9.0) / 9.0;
  if (turn > 0.85) {
    final p = (turn - 0.85) / 0.15;
    final a = math.pi * p;
    final tip = book + Offset(-w * 0.07 * math.cos(a) + w * 0.01 * (1 - math.cos(a)) * 0.5, -h * 0.03 - math.sin(a) * h * 0.02);
    c.drawLine(book + Offset(0, h * 0.01), tip, Paint()
      ..color = const Color(0xFFFFFAF0)
      ..strokeWidth = 2);
  }
  // Her arm round to the book.
  final arm = Path()
    ..moveTo(shoulder.dx - w * 0.02, shoulder.dy + h * 0.008)
    ..quadraticBezierTo(shoulder.dx - w * 0.02, shoulder.dy + h * 0.06, book.dx + w * 0.03, book.dy + h * 0.02)
    ..lineTo(book.dx + w * 0.02, book.dy + h * 0.004)
    ..quadraticBezierTo(shoulder.dx - w * 0.06, shoulder.dy + h * 0.04, shoulder.dx - w * 0.05, shoulder.dy)
    ..close();
  c.drawPath(arm, Paint()..color = jumperShade);
  c.drawOval(Rect.fromCenter(center: book + Offset(w * 0.018, h * 0.008), width: w * 0.03, height: w * 0.024), Paint()..color = _skin);
  // Her head, bowed to the page, nodding now and then.
  final neck = shoulder + Offset(-w * 0.01, -h * 0.012);
  c.save();
  c.translate(neck.dx, neck.dy);
  c.rotate(-0.05 + 0.03 * _sway(t, 5.2));
  c.translate(-neck.dx, -neck.dy);
  final r = w * 0.068;
  final head = neck + Offset(-r * 0.35, -r * 1.05);
  c.drawRect(Rect.fromCenter(center: neck + Offset(0, -h * 0.006), width: r * 0.5, height: h * 0.02), Paint()..color = _skinShade);
  c.drawCircle(head, r, Paint()..color = _skin);
  // Nose, closed eye, a little blush, facing the book.
  final face = Paint()..color = _skin;
  c.drawCircle(head + Offset(-r * 0.98, r * 0.1), r * 0.16, face);
  c.drawLine(head + Offset(-r * 0.62, -r * 0.02), head + Offset(-r * 0.4, r * 0.04), Paint()
    ..color = const Color(0xFF3A2620)
    ..strokeWidth = 1.6
    ..strokeCap = StrokeCap.round);
  c.drawCircle(head + Offset(-r * 0.45, r * 0.32), r * 0.13, Paint()..color = const Color(0x55E57A6A));
  // The bob: over the back and top of her head, a fringe to her brow.
  final bob = Path()
    ..moveTo(head.dx - r * 0.7, head.dy - r * 0.45)
    ..quadraticBezierTo(head.dx - r * 0.2, head.dy - r * 1.35, head.dx + r * 0.75, head.dy - r * 0.75)
    ..quadraticBezierTo(head.dx + r * 1.3, head.dy + r * 0.1, head.dx + r * 0.95, head.dy + r * 0.95)
    ..lineTo(head.dx + r * 0.1, head.dy + r * 0.95)
    ..quadraticBezierTo(head.dx + r * 0.25, head.dy + r * 0.2, head.dx - r * 0.1, head.dy - r * 0.2)
    ..quadraticBezierTo(head.dx - r * 0.45, head.dy - r * 0.15, head.dx - r * 0.7, head.dy - r * 0.45)
    ..close();
  c.drawPath(bob, Paint()..color = hair);
  c.restore();
}

// --------------------------------------------------------------------------
// Sunny nook: reading in an armchair by a big garden window on a bright
// day, clouds drifting by, dust in the sunbeams and the cat asleep.

Rect _sunWindow(Size s) => Rect.fromLTRB(s.width * 0.12, s.height * 0.07, s.width * 0.88, s.height * 0.54);

Path _sunArch(Size s) {
  final r = _sunWindow(s);
  return Path()
    ..moveTo(r.left, r.bottom)
    ..lineTo(r.left, r.top + r.width / 2)
    ..arcToPoint(Offset(r.right, r.top + r.width / 2), radius: Radius.circular(r.width / 2))
    ..lineTo(r.right, r.bottom)
    ..close();
}

void _studySunBase(Canvas c, Size size) {
  final w = size.width, h = size.height;
  _gradient(c, size, const [Color(0xFFF1E4CF), Color(0xFFEAD7BB), Color(0xFFE2CCAA)], const [0, 0.6, 1]);
  final win = _sunWindow(size);
  final arch = _sunArch(size);
  c.save();
  c.clipPath(arch);
  c.drawRect(
    win,
    Paint()
      ..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF7FC1EC), Color(0xFFCDE9F7)])
          .createShader(win),
  );
  _glow(c, Offset(win.right - w * 0.05, win.top + h * 0.06), w * 0.3, const Color(0x99FFF8DC));
  // Hills, trees and a hedge of flowers.
  final far = Path()..moveTo(win.left, h * 0.42);
  for (var i = 0; i <= 8; i++) {
    far.lineTo(win.left + win.width * i / 8, h * (0.4 + 0.025 * math.sin(i * 1.3)));
  }
  far
    ..lineTo(win.right, win.bottom)
    ..lineTo(win.left, win.bottom)
    ..close();
  c.drawPath(far, Paint()..color = const Color(0xFFB9DDA4));
  for (var i = 0; i < 4; i++) {
    final tx = win.left + win.width * (0.12 + i * 0.26);
    final ty = h * (0.41 + (i % 2) * 0.02);
    c.drawLine(Offset(tx, ty), Offset(tx, ty + h * 0.05), Paint()
      ..color = const Color(0xFFA88A6A)
      ..strokeWidth = 4);
    c.drawCircle(Offset(tx, ty), w * (0.07 + (i % 2) * 0.02), Paint()..color = i.isEven ? const Color(0xFF9CCB8A) : const Color(0xFFAED69A));
  }
  c.drawRect(Rect.fromLTRB(win.left, h * 0.48, win.right, win.bottom), Paint()..color = const Color(0xFF94C783));
  for (var i = 0; i < 30; i++) {
    final sd = _seeds[i + 90];
    c.drawCircle(Offset(win.left + sd[0] * win.width, h * (0.485 + sd[1] * 0.05)), 2 + sd[2] * 2,
        Paint()..color = [const Color(0xFFFFE07A), const Color(0xFFFFFFFF), const Color(0xFFF59AB3)][i % 3]);
  }
  c.restore();
  // The frame, glazing bars and sill.
  final frame = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 8
    ..color = const Color(0xFFFBF8F1);
  c.drawPath(arch, frame);
  c.drawLine(Offset(win.center.dx, win.top), Offset(win.center.dx, win.bottom), frame..strokeWidth = 5);
  c.drawLine(Offset(win.left, h * 0.36), Offset(win.right, h * 0.36), frame);
  c.drawRect(Rect.fromLTRB(w * 0.08, win.bottom, w * 0.92, win.bottom + h * 0.016), Paint()..color = const Color(0xFFFBF8F1));
  // Sunbeams falling into the room.
  final beam = Path()
    ..moveTo(win.left + win.width * 0.2, win.bottom)
    ..lineTo(win.right, win.bottom)
    ..lineTo(w * 0.98, h * 0.95)
    ..lineTo(w * 0.1, h * 0.95)
    ..close();
  c.drawPath(
    beam,
    Paint()
      ..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x55FFF6D8), Color(0x00FFF6D8)])
          .createShader(Rect.fromLTRB(0, win.bottom, w, h * 0.95)),
  );
  // The floor and a round rug.
  c.drawRect(
    Rect.fromLTRB(0, h * 0.82, w, h),
    Paint()
      ..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFE6CFA9), Color(0xFFDAC096)])
          .createShader(Rect.fromLTRB(0, h * 0.82, w, h)),
  );
  c.drawOval(Rect.fromCenter(center: Offset(w * 0.38, h * 0.915), width: w * 0.62, height: h * 0.07), Paint()..color = const Color(0xFFF0C4AE));
  c.drawOval(Rect.fromCenter(center: Offset(w * 0.38, h * 0.915), width: w * 0.48, height: h * 0.05), Paint()..color = const Color(0xFFF6D6C6));
  // A big plant on the left.
  final pot = Rect.fromLTWH(w * 0.04, h * 0.76, w * 0.16, h * 0.08);
  c.drawRRect(RRect.fromRectAndRadius(pot, const Radius.circular(6)), Paint()..color = const Color(0xFFE0A58E));
  _plant(c, Offset(pot.center.dx, pot.top + 4), w * 0.2, const Color(0xFF94BF8E));
  // The armchair, on the right.
  final chair = RRect.fromRectAndRadius(Rect.fromLTRB(w * 0.52, h * 0.66, w * 0.96, h * 0.9), const Radius.circular(22));
  c.drawRRect(chair, Paint()..color = const Color(0xFFF1E6D2));
  c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(w * 0.5, h * 0.76, w * 0.62, h * 0.9), const Radius.circular(16)), Paint()..color = const Color(0xFFE6D8BF));
  c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(w * 0.86, h * 0.76, w * 0.98, h * 0.9), const Radius.circular(16)), Paint()..color = const Color(0xFFE6D8BF));
  c.drawRect(Rect.fromLTRB(w * 0.56, h * 0.9, w * 0.58, h * 0.93), Paint()..color = const Color(0xFFB89A78));
  c.drawRect(Rect.fromLTRB(w * 0.9, h * 0.9, w * 0.92, h * 0.93), Paint()..color = const Color(0xFFB89A78));
  // A side table with a mug.
  c.drawRect(Rect.fromLTRB(w * 0.36, h * 0.775, w * 0.47, h * 0.785), Paint()..color = const Color(0xFFCFAF8A));
  c.drawLine(Offset(w * 0.415, h * 0.785), Offset(w * 0.415, h * 0.86), Paint()
    ..color = const Color(0xFFCFAF8A)
    ..strokeWidth = 4);
  _mug(c, Offset(w * 0.4, h * 0.775), w * 0.05, const Color(0xFFF7F2E8));
}

void _studySunMotion(Canvas c, Size size, double t) {
  final w = size.width, h = size.height;
  final win = _sunWindow(size);
  // Clouds drifting across the sky.
  c.save();
  c.clipPath(_sunArch(size));
  for (var i = 0; i < 3; i++) {
    final p = ((t / (55 + i * 12)) + i * 0.37) % 1.0;
    final x = win.left - w * 0.3 + p * (win.width + w * 0.6);
    final y = win.top + h * (0.07 + i * 0.06);
    _stamps.add(x, y, 0.9 + i * 0.25, const Color(0xEEFFFFFF), _cloudSrc);
  }
  _stamps.draw(c, _cloud);
  // Now and then a bird crosses.
  final bird = (t % 23.0) / 23.0;
  if (bird < 0.4) {
    final bx = win.left + (bird / 0.4) * win.width;
    final by = win.top + h * 0.12 + math.sin(bird * 20) * 3;
    final flap = _sway(t, 0.5) * 3;
    c.drawPath(
        Path()
          ..moveTo(bx - 6, by - flap)
          ..quadraticBezierTo(bx - 3, by - 2, bx, by)
          ..quadraticBezierTo(bx + 3, by - 2, bx + 6, by - flap),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = const Color(0xFF3A4A5A));
  }
  c.restore();
  // Dust turning in the sunbeams.
  for (var i = 0; i < 18; i++) {
    final sd = _seeds[i + 120];
    final x = w * (0.2 + sd[0] * 0.7) + _sway(t, 9 + sd[1] * 6, sd[2]) * w * 0.03;
    final y = win.bottom + (h * 0.35) * ((sd[1] + t * (0.004 + sd[3] * 0.006)) % 1.0);
    _glowDot(x, y, 2.5 + sd[2] * 2.5, Color.fromRGBO(255, 246, 210, 0.5 + 0.3 * _sway(t, 3 + sd[0] * 3, sd[3])));
  }
  _stamps.draw(c, _dot);
  _steamFrom(c, Offset(w * 0.4, h * 0.775 - w * 0.045), w * 0.05, t, alpha: 0.45);

  // The cat asleep on the rug, breathing, its tail tip twitching.
  final cat = Offset(w * 0.3, h * 0.905);
  final breath = 1 + 0.025 * _sway(t, 3.4);
  final fur = Paint()..color = const Color(0xFFEFE3D2);
  c.save();
  c.translate(cat.dx, cat.dy);
  c.scale(1, breath);
  c.drawOval(Rect.fromCenter(center: Offset.zero, width: w * 0.2, height: h * 0.04), fur);
  c.restore();
  final headC = cat + Offset(-w * 0.085, -h * 0.008);
  c.drawCircle(headC, w * 0.04, fur);
  for (final dx in [-w * 0.028, w * 0.008]) {
    c.drawPath(
        Path()
          ..moveTo(headC.dx + dx, headC.dy - w * 0.025)
          ..lineTo(headC.dx + dx + w * 0.008, headC.dy - w * 0.06)
          ..lineTo(headC.dx + dx + w * 0.024, headC.dy - w * 0.022)
          ..close(),
        fur);
  }
  final flick = _sway(t, 2.6) * 0.5 + 0.5;
  final tail = Path()
    ..moveTo(cat.dx + w * 0.09, cat.dy)
    ..quadraticBezierTo(cat.dx + w * 0.15, cat.dy + h * 0.02, cat.dx + w * 0.06 + flick * w * 0.02, cat.dy + h * 0.024 - flick * h * 0.006);
  c.drawPath(
      tail,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.018
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFEFE3D2));

  // Her, curled in the armchair with a book on her knees: a long braid, a
  // pale yellow cardigan, a page turning now and then.
  const hair = Color(0xFFB27C52), top = Color(0xFFF6E3A6), topShade = Color(0xFFEBD08A), trousers = Color(0xFFAFC1DA);
  final hip = Offset(w * 0.74, h * 0.79);
  // Knees drawn up, the book resting on them.
  final legs = Path()
    ..moveTo(hip.dx + w * 0.06, hip.dy + h * 0.02)
    ..quadraticBezierTo(hip.dx - w * 0.06, hip.dy - h * 0.06, hip.dx - w * 0.15, hip.dy - h * 0.035)
    ..quadraticBezierTo(hip.dx - w * 0.17, hip.dy + h * 0.0, hip.dx - w * 0.12, hip.dy + h * 0.035)
    ..lineTo(hip.dx + w * 0.06, hip.dy + h * 0.045)
    ..close();
  c.drawPath(legs, Paint()..color = trousers);
  c.drawOval(Rect.fromCenter(center: hip + Offset(-w * 0.15, h * 0.03), width: w * 0.06, height: h * 0.018), Paint()..color = const Color(0xFFEDE6DA));
  final body = Path()
    ..moveTo(hip.dx + w * 0.07, hip.dy + h * 0.02)
    ..quadraticBezierTo(hip.dx + w * 0.1, hip.dy - h * 0.08, hip.dx + w * 0.04, hip.dy - h * 0.12)
    ..quadraticBezierTo(hip.dx - w * 0.04, hip.dy - h * 0.12, hip.dx - w * 0.03, hip.dy - h * 0.05)
    ..lineTo(hip.dx - w * 0.01, hip.dy + h * 0.02)
    ..close();
  c.drawPath(body, Paint()..color = top);
  final book = hip + Offset(-w * 0.12, -h * 0.07);
  c.drawPath(
      Path()
        ..moveTo(book.dx, book.dy)
        ..lineTo(book.dx + w * 0.09, book.dy - h * 0.012)
        ..lineTo(book.dx + w * 0.1, book.dy + h * 0.01)
        ..lineTo(book.dx + w * 0.01, book.dy + h * 0.022)
        ..close(),
      Paint()..color = const Color(0xFFF8F2E4));
  c.drawLine(book + Offset(w * 0.05, -h * 0.006), book + Offset(w * 0.055, h * 0.016), Paint()
    ..color = const Color(0xFFD9CFC0)
    ..strokeWidth = 1.2);
  final turn = (t % 11.0) / 11.0;
  if (turn > 0.86) {
    final p = (turn - 0.86) / 0.14;
    final lift = math.sin(p * math.pi) * h * 0.02;
    c.drawLine(book + Offset(w * 0.095 - p * w * 0.09, h * 0.004 - lift), book + Offset(w * 0.05, h * 0.004), Paint()
      ..color = const Color(0xFFFFFCF4)
      ..strokeWidth = 2);
  }
  final arm = Path()
    ..moveTo(hip.dx + w * 0.02, hip.dy - h * 0.1)
    ..quadraticBezierTo(hip.dx - w * 0.04, hip.dy - h * 0.06, book.dx + w * 0.06, book.dy + h * 0.008)
    ..lineTo(book.dx + w * 0.065, book.dy - h * 0.006)
    ..quadraticBezierTo(hip.dx - w * 0.02, hip.dy - h * 0.085, hip.dx + w * 0.04, hip.dy - h * 0.11)
    ..close();
  c.drawPath(arm, Paint()..color = topShade);
  c.drawOval(Rect.fromCenter(center: book + Offset(w * 0.06, h * 0.002), width: w * 0.028, height: w * 0.022), Paint()..color = _skin);
  // Her head, bent to the book, swaying gently.
  final neck = hip + Offset(w * 0.02, -h * 0.12);
  c.save();
  c.translate(neck.dx, neck.dy);
  c.rotate(-0.12 + 0.03 * _sway(t, 6.1));
  c.translate(-neck.dx, -neck.dy);
  final r = w * 0.06;
  final head = neck + Offset(-r * 0.25, -r * 1.0);
  c.drawRect(Rect.fromCenter(center: neck + Offset(0, -h * 0.005), width: r * 0.5, height: h * 0.02), Paint()..color = _skinShade);
  c.drawCircle(head, r, Paint()..color = _skin);
  c.drawCircle(head + Offset(-r * 0.98, r * 0.12), r * 0.15, Paint()..color = _skin);
  c.drawLine(head + Offset(-r * 0.6, 0), head + Offset(-r * 0.38, r * 0.06), Paint()
    ..color = const Color(0xFF3A2620)
    ..strokeWidth = 1.5
    ..strokeCap = StrokeCap.round);
  c.drawCircle(head + Offset(-r * 0.42, r * 0.34), r * 0.12, Paint()..color = const Color(0x55E57A6A));
  final cap = Path()
    ..moveTo(head.dx - r * 0.75, head.dy - r * 0.3)
    ..quadraticBezierTo(head.dx - r * 0.3, head.dy - r * 1.3, head.dx + r * 0.75, head.dy - r * 0.7)
    ..quadraticBezierTo(head.dx + r * 1.2, head.dy, head.dx + r * 0.8, head.dy + r * 0.75)
    ..quadraticBezierTo(head.dx + r * 0.2, head.dy + r * 0.2, head.dx - r * 0.1, head.dy - r * 0.25)
    ..quadraticBezierTo(head.dx - r * 0.45, head.dy - r * 0.1, head.dx - r * 0.75, head.dy - r * 0.3)
    ..close();
  c.drawPath(cap, Paint()..color = hair);
  // The braid over her shoulder.
  final braid = Paint()..color = hair;
  for (var i = 0; i < 5; i++) {
    c.drawOval(Rect.fromCenter(center: head + Offset(r * (0.55 - i * 0.12), r * (0.9 + i * 0.42)), width: r * 0.42, height: r * 0.5), braid);
  }
  c.restore();
}
