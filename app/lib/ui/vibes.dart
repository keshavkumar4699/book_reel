
import 'package:flutter/material.dart';

import '../data/settings.dart';
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
  // Morning in the pines: deep pine ink on a morning-mist veil, amber emphasis.
  Vibe.forest: ScenePalette(
    ink: Color(0xFF1B2A20),
    emphasis: Color(0xFF6B3A0B),
    spot: Color(0xFF142019),
    accent: Color(0xFF1B2A20),
    tint: Color(0xFFF8FAF0),
    shade: [0.08, 0.08, 0.08, 0.08, 0.10, 0.20, 0.22, 0.22, 0.20, 0.14, 0.12],
    lightInk: false,
  ),
  // Latte foam on espresso; caramel emphasis.
  Vibe.cafe: ScenePalette(
    ink: Color(0xFFF7EADB),
    emphasis: Color(0xFFF7C089),
    spot: Color(0xFFFFEBD2),
    accent: Color(0xFFF7EADB),
    tint: Color(0xFF170D07),
    shade: [0.14, 0.20, 0.32, 0.44, 0.44, 0.33, 0.33, 0.28, 0.28, 0.28, 0.30],
  ),
  // Cool mist on rain-night navy; rain-sky blue emphasis.
  Vibe.rain: ScenePalette(
    ink: Color(0xFFE8EFF7),
    emphasis: Color(0xFFAFD3F8),
    spot: Color(0xFFF3F8FF),
    accent: Color(0xFFE8EFF7),
    tint: Color(0xFF060D19),
    shade: [0.14, 0.14, 0.14, 0.16, 0.28, 0.28, 0.16, 0.14, 0.14, 0.24, 0.30],
  ),
  // A bright shore: deep sea-navy ink on a sunlit veil, coral-brown emphasis.
  Vibe.ocean: ScenePalette(
    ink: Color(0xFF12283A),
    emphasis: Color(0xFF7A2E10),
    spot: Color(0xFF0C1F2E),
    accent: Color(0xFF12283A),
    tint: Color(0xFFFBFCF8),
    shade: [0.08, 0.08, 0.08, 0.08, 0.08, 0.10, 0.10, 0.10, 0.10, 0.08, 0.08],
    lightInk: false,
  ),
  // Moonlight on midnight blue; lavender emphasis.
  Vibe.night: ScenePalette(
    ink: Color(0xFFECEBF8),
    emphasis: Color(0xFFD3C7FF),
    spot: Color(0xFFF8F5FF),
    accent: Color(0xFFECEBF8),
    tint: Color(0xFF04071A),
    shade: [0.14, 0.14, 0.14, 0.14, 0.14, 0.14, 0.14, 0.14, 0.14, 0.24, 0.30],
  ),
  // A bright day: deep moss ink on a soft sunlit veil, dark honey emphasis.
  Vibe.meadow: ScenePalette(
    ink: Color(0xFF24301F),
    emphasis: Color(0xFF6B3F0C),
    spot: Color(0xFF1C2618),
    accent: Color(0xFF24301F),
    tint: Color(0xFFFFFAEC),
    shade: [0.08, 0.08, 0.08, 0.08, 0.09, 0.21, 0.33, 0.45, 0.45, 0.33, 0.21],
    lightInk: false,
  ),
  // A snow day: slate ink on a frosty veil, deep winter-blue emphasis.
  Vibe.snow: ScenePalette(
    ink: Color(0xFF18233A),
    emphasis: Color(0xFF1C4785),
    spot: Color(0xFF111A2D),
    accent: Color(0xFF18233A),
    tint: Color(0xFFF6F9FD),
    shade: [0.08, 0.08, 0.08, 0.08, 0.08, 0.10, 0.14, 0.26, 0.32, 0.30, 0.16],
    lightInk: false,
  ),
  // Pale neon on night violet; soft neon-rose emphasis.
  Vibe.city: ScenePalette(
    ink: Color(0xFFF2ECF7),
    emphasis: Color(0xFFFFB8DC),
    spot: Color(0xFFFFF3FA),
    accent: Color(0xFFF2ECF7),
    tint: Color(0xFF0A0617),
    shade: [0.14, 0.14, 0.14, 0.14, 0.14, 0.14, 0.25, 0.37, 0.37, 0.25, 0.30],
  ),
};

/// Daytime scenes (dark text on a bright scene), then evening and night ones
/// (light text on a dark scene), in the order the picker shows them. Paper
/// follows the app's light or dark.
const dayScenes = [Vibe.meadow, Vibe.forest, Vibe.ocean, Vibe.snow];
const nightScenes = [Vibe.night, Vibe.rain, Vibe.city, Vibe.cafe];

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
  Vibe.forest: VibeStyle(label: 'Forest morning', emoji: '🌲', tagline: 'Sun through the pines', accent: Color(0xFF1B2A20), dark: false),
  Vibe.cafe: VibeStyle(label: 'Café', emoji: '☕', tagline: 'Rainy evening, warm cup', accent: Color(0xFFFFB86B)),
  Vibe.rain: VibeStyle(label: 'Rain', emoji: '🌧️', tagline: 'City lights through rain', accent: Color(0xFF8FC1FF)),
  Vibe.ocean: VibeStyle(label: 'Beach', emoji: '🏖️', tagline: 'Bright surf on the sand', accent: Color(0xFF12283A), dark: false),
  Vibe.night: VibeStyle(label: 'Night', emoji: '🌙', tagline: 'Stars over the mountains', accent: Color(0xFFC9B8FF)),
  Vibe.meadow: VibeStyle(label: 'Meadow', emoji: '🌼', tagline: 'Sunny meadow, drifting clouds', accent: Color(0xFF224D1F), dark: false),
  Vibe.snow: VibeStyle(label: 'Snow day', emoji: '❄️', tagline: 'White hills, soft snowfall', accent: Color(0xFF18233A), dark: false),
  Vibe.city: VibeStyle(label: 'City', emoji: '🌃', tagline: 'Skyline lights at night', accent: Color(0xFFFF8FC7)),
  Vibe.paper: VibeStyle(label: 'Paper', emoji: '📄', tagline: 'Plain and focused', accent: Color(0xFF111111), dark: false),
};

/// Reading-surface colours on top of a scene (the scene's palette).
ReadingTheme readingThemeForVibe(Vibe vibe, ReadingTheme paper) => readingThemeForPalette(scenePalettes[vibe], paper);

/// Reading-surface colours on top of a scene or picture with palette [p]
/// (none: the plain page in the reading theme's own colours).
ReadingTheme readingThemeForPalette(ScenePalette? p, ReadingTheme paper) {
  if (p == null) return paper;
  return ReadingTheme(
    background: const Color(0x00000000),
    text: p.ink,
    muted: p.muted,
    keyPoint: p.emphasis.withValues(alpha: 0.24),
    hardWordUnderline: p.emphasis,
    // Tints of the scene's own colour, with the scene's darkest (or lightest)
    // colour as the text on them.
    highlights: highlightFills(darkSurface: p.lightInk, family: p.emphasis),
    highlightInk: p.tint,
    isDark: p.lightInk,
    glass: p.lightInk ? p.tint.withValues(alpha: 0.62) : p.tint.withValues(alpha: 0.78),
    emphasis: p.emphasis,
    spot: p.spot,
    accent: p.accent,
    scrim: p.scrim,
    textShadows: p.textShadows,
  );
}

