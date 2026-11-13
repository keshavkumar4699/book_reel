import 'dart:io';
import 'dart:math' as math;

import 'package:book_reel/data/settings.dart';
import 'package:book_reel/ui/kit.dart';
import 'package:book_reel/ui/theme.dart';
import 'package:book_reel/ui/vibes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Every kit the app can wear: each scene, and plain paper in light and dark.
Iterable<(String, Kit)> _kits() sync* {
  for (final v in Vibe.values) {
    if (v == Vibe.paper) continue;
    yield (v.name, Kit.forScene(v, ReadingTheme.of(ReadingThemeId.paper)));
  }
  for (final t in ReadingThemeId.values) {
    yield ('paper/${t.name}', Kit.forScene(Vibe.paper, ReadingTheme.of(t)));
  }
  yield ('app light', Kit.appLight);
  yield ('app dark', Kit.appDark);
}

Widget _app(Widget child, {Kit? kit}) => MaterialApp(
      theme: buildAppTheme(kit ?? Kit.forScene(Vibe.forest, ReadingTheme.of(ReadingThemeId.paper))),
      home: Scaffold(body: child),
    );

void main() {
  test('sheets, dialogs and toasts keep text readable in every scene', () {
    for (final (name, kit) in _kits()) {
      expect(kit.sheet.a, 1, reason: '$name: sheets are opaque, so nothing ghosts through');
      expect(_contrast(kit.ink, kit.sheet), greaterThanOrEqualTo(7), reason: '$name ink (AAA)');
      expect(_contrast(Color.alphaBlend(kit.inkSoft, kit.sheet), kit.sheet), greaterThanOrEqualTo(4.5), reason: '$name secondary text');
      // Primary buttons, selected chips and segments are filled with ink.
      expect(_contrast(kit.inverse, kit.ink), greaterThanOrEqualTo(7), reason: '$name text on an ink fill');
      // The logo red is only for icons (flame, liked heart) and badges: 3:1.
      expect(_contrast(kit.accent, kit.sheet), greaterThanOrEqualTo(3), reason: '$name logo red icon');
      expect(_contrast(kit.onAccent, kit.accent), greaterThanOrEqualTo(3), reason: '$name badge count');
    }
  });

  test('the app is white, black and greys; the logo red only for flame, liked heart and badges', () {
    for (final kit in [Kit.appLight, Kit.appDark]) {
      for (final c in [kit.base, kit.sheet, kit.glass, kit.ink, kit.inkSoft]) {
        expect((c.r - c.g).abs() < 0.01 && (c.g - c.b).abs() < 0.01, isTrue, reason: '$c is a neutral');
      }
    }
    expect(Kit.gradient.colors, [const Color(0xFFFF3131), const Color(0xFFFF914D)]);
    expect(Kit.appLight.accent, const Color(0xFFFF3131));
    // Only these places may use the logo red (or its gradient).
    const allowed = ['local_fire_department', 'favorite', 'Heart', 'liked', 'ShareTemplate', 'KitBadge', 'badge'];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      if (f.path.endsWith('ui/theme.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i];
        if (!RegExp(r'kit\.accent|\bember\b|Kit\.gradient').hasMatch(l)) continue;
        if (l.trimLeft().startsWith('//') || l.trimLeft().startsWith('///')) continue;
        if (f.path.endsWith('ui/kit.dart') && (l.contains('static const') || l.contains('accent:') || l.contains('decoration: BoxDecoration(color: kit.accent'))) continue;
        expect(allowed.any(l.contains), isTrue, reason: '${f.path}:${i + 1} uses the logo colour: $l');
      }
    }
    // The reader's sheets and menus use the same neutrals, whatever the scene.
    expect(Kit.forScene(Vibe.night, ReadingTheme.of(ReadingThemeId.paper)).sheet, Kit.appDark.sheet);
    expect(Kit.forScene(Vibe.forest, ReadingTheme.of(ReadingThemeId.paper)).sheet, Kit.appLight.sheet, reason: 'a day scene');
    expect(Kit.forScene(Vibe.meadow, ReadingTheme.of(ReadingThemeId.paper)).sheet, Kit.appLight.sheet);
  });

  testWidgets('option groups are flat: no box, no line between options, one line between groups', (tester) async {
    await tester.pumpWidget(_app(ListView(children: const [
      KitGroup(label: 'One', children: [KitRow(title: 'a', icon: Icons.star), KitRow(title: 'b', icon: Icons.star)]),
      KitGroup(label: 'Two', divided: true, children: [KitRow(title: 'c'), KitRow(title: 'd')]),
    ]), kit: Kit.appLight));
    expect(find.byType(KitDivider), findsOneWidget, reason: 'only between the two groups');
    expect(find.byType(KitPanel), findsNothing);
    final decorated = tester.widgetList<Container>(find.descendant(of: find.byType(KitGroup), matching: find.byType(Container)))
        .where((c) => c.decoration is BoxDecoration && (c.decoration! as BoxDecoration).border != null);
    expect(decorated, isEmpty, reason: 'no bordered boxes');
    // Row icons are plain ink icons, not tinted squares.
    expect(tester.widget<Icon>(find.byIcon(Icons.star).first).color, Kit.appLight.ink);
  });

  testWidgets('a toast drops in, lets taps through to what is under it, and leaves', (tester) async {
    var taps = 0;
    late BuildContext ctx;
    await tester.pumpWidget(_app(Builder(builder: (context) {
      ctx = context;
      // A control right where the toast appears.
      return Align(
        alignment: Alignment.topCenter,
        child: Padding(padding: const EdgeInsets.only(top: 80), child: KitButton(label: 'Under', onPressed: () => taps++)),
      );
    })));
    showKitToast(ctx, 'Saved to your Notebook', icon: Icons.bookmark_rounded);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Saved to your Notebook'), findsOneWidget);
    await tester.tap(find.text('Under'), warnIfMissed: false);
    expect(taps, 1);
    // A newer toast replaces it.
    showKitToast(ctx, 'Removed from saved');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Saved to your Notebook'), findsNothing);
    expect(find.text('Removed from saved'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Removed from saved'), findsNothing);
  });

  testWidgets('a toast with an action runs it', (tester) async {
    var noted = false;
    late BuildContext ctx;
    await tester.pumpWidget(_app(Builder(builder: (context) {
      ctx = context;
      return const SizedBox.expand();
    })));
    showKitToast(ctx, 'Highlighted', actionLabel: 'Add note', onAction: () => noted = true);
    await tester.pump(); // animations start on the first frame
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Add note'));
    await tester.pumpAndSettle();
    expect(noted, isTrue);
    expect(find.text('Highlighted'), findsNothing);
  });

  testWidgets('sheets return the picked action and close when dragged down', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(_app(Builder(builder: (context) {
      ctx = context;
      return const SizedBox.expand();
    })));
    final picked = showKitActions<String>(ctx, title: 'Book', actions: const [
      KitAction('read', 'Read', icon: Icons.play_arrow_rounded),
      KitAction('remove', 'Remove', icon: Icons.delete_outline_rounded, destructive: true),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Book'), findsOneWidget);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(await picked, 'remove');

    final closed = showKitSheet<String>(ctx, title: 'Drag me', builder: (_) => const SizedBox(height: 300));
    await tester.pumpAndSettle();
    await tester.drag(find.text('Drag me'), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(find.text('Drag me'), findsNothing);
    expect(await closed, isNull);
  });

  testWidgets('prompt returns trimmed text; cancel returns nothing', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(_app(Builder(builder: (context) {
      ctx = context;
      return const SizedBox.expand();
    })));
    var answer = showKitPrompt(ctx, title: 'Your name');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '  Asha  ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(await answer, 'Asha');
    answer = showKitPrompt(ctx, title: 'Your name');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await answer, isNull);
  });

  testWidgets('switch rows, segments and sliders change their values', (tester) async {
    var on = false;
    var seg = 'Bite';
    var size = 20.0;
    await tester.pumpWidget(_app(StatefulBuilder(builder: (context, setState) {
      return Column(children: [
        KitSwitchRow(title: 'Underline hard words', value: on, onChanged: (v) => setState(() => on = v)),
        KitSegmented<String>(values: const ['Snack', 'Bite', 'Deep'], selected: seg, label: (v) => v, onChanged: (v) => setState(() => seg = v)),
        SizedBox(
          width: 300,
          child: KitSlider(value: size, min: 14, max: 32, divisions: 18, semanticLabel: 'Text size', onChanged: (v) => setState(() => size = v)),
        ),
      ]);
    })));
    await tester.tap(find.text('Underline hard words'));
    await tester.pump();
    expect(on, isTrue);
    await tester.tap(find.text('Deep'));
    await tester.pump();
    expect(seg, 'Deep');
    // Tapping the far right end snaps to the maximum.
    final slider = tester.getRect(find.byType(KitSlider));
    await tester.tapAt(Offset(slider.right - 2, slider.center.dy));
    await tester.pump();
    expect(size, 32);
    expect(tester.getSemantics(find.byType(KitSlider)), matchesSemantics(isSlider: true, label: 'Text size', value: '32.0',
        increasedValue: '32.0', decreasedValue: '31.0', hasIncreaseAction: true, hasDecreaseAction: true));
  });

  test('backgrounds of the same scene and size share one cached image, freed when unused', () {
    const size = Size(412, 915);
    final a = SceneBases.acquire(Vibe.rain, size, 1)!;
    final b = SceneBases.acquire(Vibe.rain, size, 1)!;
    expect(identical(a, b), isTrue);
    SceneBases.release(a);
    SceneBases.release(b);
    expect(a.image.debugDisposed, isFalse, reason: 'kept for a moment in case the scene comes back');
    // Three other unused scenes later, it is freed.
    for (final v in [Vibe.snow, Vibe.city, Vibe.night]) {
      SceneBases.release(SceneBases.acquire(v, size, 1)!);
    }
    expect(a.image.debugDisposed, isTrue);
    // Paper and thumbnails-sized keys are never cached.
    expect(SceneBases.keyFor(Vibe.paper, size, 1), isNull);
  });

  testWidgets('a moving scene ticks about 30 times a second and stops when its route is covered', (tester) async {
    await tester.pumpWidget(_app(const VibeBackground(vibe: Vibe.forest)));
    ScenePainter.debugPaintCount = 0;
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    // ~1 s of 60 Hz frames: the scene repaints on its own 30 fps clock only.
    expect(ScenePainter.debugPaintCount, inInclusiveRange(20, 40));
    await tester.pumpWidget(_app(const TickerMode(enabled: false, child: VibeBackground(vibe: Vibe.forest))));
    await tester.pump(const Duration(milliseconds: 100));
    ScenePainter.debugPaintCount = 0;
    await tester.pump(const Duration(milliseconds: 500));
    expect(ScenePainter.debugPaintCount, 0, reason: 'no repaints while the scene is hidden');
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
