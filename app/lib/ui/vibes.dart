
import 'package:flutter/material.dart';

import '../data/settings.dart';
import 'kit.dart';
import 'scenes.dart';
import 'theme.dart';

export 'scenes.dart';

/// Text colours for one scene, chosen to sit naturally on it:
///
/// * ink is a tinted off-white (or a deep ink on the bright meadow), never
///   pure white, which "vibrates" and blooms on dark scenes;
/// * the shade over the scene uses the scene's own darkest hue rather than
///   grey, so colours stay rich instead of muddy;
/// * the shade's strength varies down the screen, measured from the painted
///   scene: body text keeps ≥ 7:1 contrast (WCAG AAA) where it sits (the
///   middle 60 % of the screen) and every text colour and control keeps
///   ≥ 4.5:1 (AA) everywhere, while dark parts of the scene stay untouched
///   (test/ui/scene_palette_test.dart checks this on the rendered scenes).
class ScenePalette {
  const ScenePalette({
    required this.ink,
    required this.emphasis,
    required this.spot,
    required this.accent,
    required this.tint,
    required this.shade,
    this.lightInk = true,
  });

  /// Body text.
  final Color ink;

  /// Inline emphasis: same size as the body, a warmer or brighter tone.
  final Color emphasis;

  /// Spotlight lines in large display type.
  final Color spot;

  /// Labels and active controls.
  final Color accent;

  /// Colour of the shade (dark scenes) or veil (light scenes).
  final Color tint;

  /// Shade opacity at 0 %, 10 %, … 100 % of the screen height.
  final List<double> shade;

  /// Light text on a darkened scene (false: dark text on a light veil).
  final bool lightInk;

  Color get muted => ink.withValues(alpha: lightInk ? 0.74 : 0.8);

  LinearGradient get scrim => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [for (final a in shade) tint.withValues(alpha: a)],
        stops: [for (var i = 0; i < shade.length; i++) i / (shade.length - 1)],
      );

  /// One soft, small shadow that lifts text off the scene. (The shade already
  /// gives the contrast; a wide or double shadow would be re-blurred on every
  /// frame the scene moves.)
  List<Shadow> get textShadows => lightInk
      ? [Shadow(color: tint.withValues(alpha: 0.6), blurRadius: 5, offset: const Offset(0, 1))]
      : [Shadow(color: tint.withValues(alpha: 0.85), blurRadius: 6)];
}

const scenePalettes = <Vibe, ScenePalette>{
  // Parchment on deep pine; honey for emphasis.
  Vibe.forest: ScenePalette(
    ink: Color(0xFFF4EEDD),
    emphasis: Color(0xFFF3D38C),
    spot: Color(0xFFFFF5DC),
    accent: Color(0xFFF2C46D),
    tint: Color(0xFF0C1A12),
    shade: [0.14, 0.23, 0.35, 0.47, 0.47, 0.35, 0.23, 0.14, 0.14, 0.24, 0.30],
  ),
  // Latte foam on espresso; caramel emphasis.
  Vibe.cafe: ScenePalette(
    ink: Color(0xFFF7EADB),
    emphasis: Color(0xFFF7C089),
    spot: Color(0xFFFFEBD2),
    accent: Color(0xFFFFB86B),
    tint: Color(0xFF170D07),
    shade: [0.14, 0.20, 0.32, 0.44, 0.44, 0.33, 0.33, 0.28, 0.28, 0.28, 0.30],
  ),
  // Cool mist on rain-night navy; rain-sky blue emphasis.
  Vibe.rain: ScenePalette(
    ink: Color(0xFFE8EFF7),
    emphasis: Color(0xFFAFD3F8),
    spot: Color(0xFFF3F8FF),
    accent: Color(0xFF8FC1FF),
    tint: Color(0xFF060D19),
    shade: [0.14, 0.14, 0.14, 0.16, 0.28, 0.28, 0.16, 0.14, 0.14, 0.24, 0.30],
  ),
  // Seashell on dusk indigo; sunset peach emphasis.
  Vibe.ocean: ScenePalette(
    ink: Color(0xFFFBF0E9),
    emphasis: Color(0xFFFFC9A8),
    spot: Color(0xFFFFF2E8),
    accent: Color(0xFFFFB38A),
    tint: Color(0xFF120D24),
    shade: [0.14, 0.14, 0.14, 0.17, 0.29, 0.41, 0.52, 0.52, 0.40, 0.28, 0.30],
  ),
  // Moonlight on midnight blue; lavender emphasis.
  Vibe.night: ScenePalette(
    ink: Color(0xFFECEBF8),
    emphasis: Color(0xFFD3C7FF),
    spot: Color(0xFFF8F5FF),
    accent: Color(0xFFC9B8FF),
    tint: Color(0xFF04071A),
    shade: [0.14, 0.14, 0.14, 0.14, 0.14, 0.14, 0.14, 0.14, 0.14, 0.24, 0.30],
  ),
  // A bright day: deep moss ink on a soft sunlit veil, dark honey emphasis.
  Vibe.meadow: ScenePalette(
    ink: Color(0xFF24301F),
    emphasis: Color(0xFF6B3F0C),
    spot: Color(0xFF1C2618),
    accent: Color(0xFF224D1F),
    tint: Color(0xFFFFFAEC),
    shade: [0.08, 0.08, 0.08, 0.08, 0.09, 0.21, 0.33, 0.45, 0.45, 0.33, 0.21],
    lightInk: false,
  ),
  // Frost on winter navy; ice-blue emphasis.
  Vibe.snow: ScenePalette(
    ink: Color(0xFFEEF3FA),
    emphasis: Color(0xFFBCDDFF),
    spot: Color(0xFFF7FAFF),
    accent: Color(0xFFA8D8FF),
    tint: Color(0xFF0D1526),
    shade: [0.14, 0.14, 0.14, 0.14, 0.14, 0.26, 0.38, 0.50, 0.50, 0.44, 0.40],
  ),
  // Pale neon on night violet; soft neon-rose emphasis.
  Vibe.city: ScenePalette(
    ink: Color(0xFFF2ECF7),
    emphasis: Color(0xFFFFB8DC),
    spot: Color(0xFFFFF3FA),
    accent: Color(0xFFFF8FC7),
    tint: Color(0xFF0A0617),
    shade: [0.14, 0.14, 0.14, 0.14, 0.14, 0.14, 0.25, 0.37, 0.37, 0.25, 0.30],
  ),
};

/// Visual style for each calm "study vibe".
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

  /// Light text on this scene.
  final bool dark;

  Color get text => dark ? const Color(0xFFF4EFE6) : const Color(0xFF1F1D1A);
  Color get muted => dark ? const Color(0xBDF4EFE6) : const Color(0xFF5E584F);
  Color get glass => dark ? const Color(0x9E10131A) : const Color(0xE6FFFDF8);
  Color get glassBorder => dark ? const Color(0x24FFFFFF) : const Color(0x14000000);
}

const vibeStyles = <Vibe, VibeStyle>{
  Vibe.forest: VibeStyle(label: 'Forest', emoji: '🌲', tagline: 'Pines at dusk, fireflies', accent: Color(0xFFF2C46D)),
  Vibe.cafe: VibeStyle(label: 'Café', emoji: '☕', tagline: 'Rainy evening, warm cup', accent: Color(0xFFFFB86B)),
  Vibe.rain: VibeStyle(label: 'Rain', emoji: '🌧️', tagline: 'City lights through rain', accent: Color(0xFF8FC1FF)),
  Vibe.ocean: VibeStyle(label: 'Ocean', emoji: '🌅', tagline: 'Slow waves after sunset', accent: Color(0xFFFFB38A)),
  Vibe.night: VibeStyle(label: 'Night', emoji: '🌙', tagline: 'Stars over the mountains', accent: Color(0xFFC9B8FF)),
  Vibe.meadow: VibeStyle(label: 'Meadow', emoji: '🌼', tagline: 'Sunny meadow, drifting clouds', accent: Color(0xFF224D1F), dark: false),
  Vibe.snow: VibeStyle(label: 'Snow', emoji: '❄️', tagline: 'Quiet cabin, falling snow', accent: Color(0xFFA8D8FF)),
  Vibe.city: VibeStyle(label: 'City', emoji: '🌃', tagline: 'Skyline lights at night', accent: Color(0xFFFF8FC7)),
  Vibe.paper: VibeStyle(label: 'Paper', emoji: '📄', tagline: 'Plain and focused', accent: ember, dark: false),
};

/// Reading-surface colours on top of a scene (the scene's palette).
ReadingTheme readingThemeForVibe(Vibe vibe, ReadingTheme paper) {
  final p = scenePalettes[vibe];
  if (p == null) return paper;
  return ReadingTheme(
    background: const Color(0x00000000),
    text: p.ink,
    muted: p.muted,
    keyPoint: p.emphasis.withValues(alpha: 0.24),
    hardWordUnderline: p.emphasis,
    highlights: p.lightInk
        ? const [Color(0x66E0A23A), Color(0x664FA873), Color(0x664A82C9), Color(0x66C85C8A)]
        : const [Color(0x59F2B84B), Color(0x5967C587), Color(0x595B9BE6), Color(0x59E87AA4)],
    isDark: p.lightInk,
    glass: p.lightInk ? p.tint.withValues(alpha: 0.62) : p.tint.withValues(alpha: 0.78),
    emphasis: p.emphasis,
    spot: p.spot,
    accent: p.accent,
    scrim: p.scrim,
    textShadows: p.textShadows,
  );
}

/// Horizontal row of scene thumbnails (static) for picking a vibe.
class VibePickerRow extends StatelessWidget {
  const VibePickerRow({
    super.key,
    required this.selected,
    required this.onSelected,
    this.height = 132,
    this.onAuto,
    this.autoSelected = false,
  });

  final Vibe selected;
  final ValueChanged<Vibe> onSelected;
  final double height;

  /// When set, shows an "Auto" tile first (AI picks the scene).
  final VoidCallback? onAuto;
  final bool autoSelected;

  @override
  Widget build(BuildContext context) {
    final ink = Kit.of(context).ink;
    return SizedBox(
      height: height + 28,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: Vibe.values.length + (onAuto == null ? 0 : 1),
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          if (onAuto != null && index == 0) return _autoTile(context);
          final v = Vibe.values[index - (onAuto == null ? 0 : 1)];
          final style = vibeStyles[v]!;
          final isSelected = !autoSelected && v == selected;
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
                Text(style.label, style: TextStyle(fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600, color: ink)),
              ]),
            ),
          );
        },
      ),
    );
  }
}

extension on VibePickerRow {
  Widget _autoTile(BuildContext context) {
    final ink = Kit.of(context).ink;
    return Semantics(
      button: true,
      selected: autoSelected,
      label: 'Auto vibe: the AI picks the scene for each chapter',
      child: GestureDetector(
        onTap: onAuto,
        child: Column(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: height * 0.62,
            height: height,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: autoSelected ? const Color(0xFFFFC66B) : Colors.transparent, width: 3),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(fit: StackFit.expand, children: [
                // A quartered preview of four scenes.
                Column(children: [
                  Expanded(child: Row(children: const [
                    Expanded(child: VibeBackground(vibe: Vibe.forest, animate: false)),
                    Expanded(child: VibeBackground(vibe: Vibe.city, animate: false)),
                  ])),
                  Expanded(child: Row(children: const [
                    Expanded(child: VibeBackground(vibe: Vibe.ocean, animate: false)),
                    Expanded(child: VibeBackground(vibe: Vibe.snow, animate: false)),
                  ])),
                ]),
                const ColoredBox(color: Color(0x33000000)),
                const Center(child: Text('✨', style: TextStyle(fontSize: 28))),
              ]),
            ),
          ),
          const SizedBox(height: 4),
          Text('Auto', style: TextStyle(fontWeight: autoSelected ? FontWeight.w800 : FontWeight.w600, color: ink)),
        ]),
      ),
    );
  }
}
