import 'package:flutter/material.dart';

import '../data/settings.dart';

/// Brand accent: the Cloro logo's red (gradient #FF3131 → #FF914D).
const emberSeed = Color(0xFFFF3131);

/// Reading-surface tokens, separate from the app chrome's colour scheme.
///
/// On a scene the text colours come from that scene's palette (see
/// `scenePalettes` in vibes.dart): tinted off-whites instead of pure white,
/// and a tinted shade ([scrim]) calibrated so body text keeps at least 7:1
/// contrast (WCAG AAA) wherever it can sit.
@immutable
class ReadingTheme extends ThemeExtension<ReadingTheme> {
  const ReadingTheme({
    required this.background,
    required this.text,
    required this.muted,
    required this.keyPoint,
    required this.hardWordUnderline,
    required this.highlights,
    required this.isDark,
    this.glass = const Color(0x00000000),
    Color? emphasis,
    Color? spot,
    Color? accent,
    this.scrim,
    this.textShadows,
    Color? highlightInk,
  })  : emphasis = emphasis ?? text,
        spot = spot ?? text,
        accent = accent ?? text,
        highlightInk = highlightInk ?? background;

  final Color background;
  final Color text;
  final Color muted;
  final Color keyPoint;
  final Color hardWordUnderline;
  final List<Color> highlights;
  final bool isDark;

  /// Tint of the card panel when text sits on a scene (transparent on paper).
  final Color glass;

  /// Inline emphasis (same size as the text, brighter or warmer); ≥ 4.5:1.
  final Color emphasis;

  /// Spotlight lines (large display type).
  final Color spot;

  /// Labels and active controls (chapter label, goal bar, saved icon).
  final Color accent;

  /// Shade drawn over the scene behind text; null on plain paper themes.
  final Gradient? scrim;

  /// Soft shadows that lift text off the scene (null on paper).
  final List<Shadow>? textShadows;

  /// Text on a highlight: the opposite shade of the [highlights] fills.
  final Color highlightInk;

  /// True when the reading surface is a scene rather than plain paper.
  bool get onScene => scrim != null;

  static ReadingTheme of(ReadingThemeId id) => _themes[id]!;

  static final _themes = {for (final id in ReadingThemeId.values) id: _build(id)};

  static ReadingTheme _build(ReadingThemeId id) => switch (id) {
        ReadingThemeId.paper => ReadingTheme(
            background: Color(0xFFFBF8F1),
            text: Color(0xFF1F1D1A),
            muted: Color(0xFF6E685E),
            keyPoint: Color(0x33E0A84A),
            hardWordUnderline: Color(0xFFB07A2E),
            highlights: _lightHighlights,
            isDark: false,
            emphasis: Color(0xFF8A4B12),
            accent: Color(0xFF1F1D1A),
          ),
        ReadingThemeId.white => ReadingTheme(
            background: Color(0xFFFFFFFF),
            text: Color(0xFF1A1A1A),
            muted: Color(0xFF6B6B6B),
            keyPoint: Color(0x33E0A84A),
            hardWordUnderline: Color(0xFFB07A2E),
            highlights: _lightHighlights,
            isDark: false,
            emphasis: Color(0xFF8A4B12),
            accent: Color(0xFF1A1A1A),
          ),
        ReadingThemeId.sepia => ReadingTheme(
            background: Color(0xFFF1E7D0),
            text: Color(0xFF3B2F22),
            muted: Color(0xFF6E5D49),
            keyPoint: Color(0x40D69A3C),
            hardWordUnderline: Color(0xFF9A6526),
            highlights: _lightHighlights,
            isDark: false,
            emphasis: Color(0xFF773D0B),
            accent: Color(0xFF3B2F22),
          ),
        ReadingThemeId.dark => ReadingTheme(
            background: Color(0xFF141414),
            text: Color(0xFFE6E1D6),
            muted: Color(0xFF9A948A),
            keyPoint: Color(0x33E0A84A),
            hardWordUnderline: Color(0xFFE0A84A),
            highlights: _darkHighlights,
            isDark: true,
            emphasis: Color(0xFFE9BC72),
            accent: Color(0xFFE6E1D6),
          ),
        ReadingThemeId.black => ReadingTheme(
            background: Color(0xFF000000),
            text: Color(0xFFDCD7CC),
            muted: Color(0xFF8E897F),
            keyPoint: Color(0x2EE0A84A),
            hardWordUnderline: Color(0xFFE0A84A),
            highlights: _darkHighlights,
            isDark: true,
            emphasis: Color(0xFFE2B66C),
            accent: Color(0xFFDCD7CC),
          ),
      };

  // Deep fills with light text on light pages; light fills with dark text on dark ones.
  static final _lightHighlights = highlightFills(darkSurface: false, family: const Color(0xFFF2B84B));
  static final _darkHighlights = highlightFills(darkSurface: true, family: const Color(0xFFF2B84B));

  @override
  ReadingTheme copyWith() => this;

  @override
  ReadingTheme lerp(ThemeExtension<ReadingTheme>? other, double t) => t < 0.5 ? this : (other as ReadingTheme? ?? this);
}

/// Four highlight colours that suit a reading surface, the first in its own
/// colour [family]: light tints on dark surfaces (read with dark text), deep
/// tones on light ones (read with light text), so highlighted words stay
/// clearly readable.
List<Color> highlightFills({required bool darkSurface, required Color family}) {
  const hues = [Color(0xFFF2B84B), Color(0xFF67C587), Color(0xFF5B9BE6), Color(0xFFE87AA4)];
  return [
    for (final (i, hue) in hues.indexed)
      Color.lerp(i == 0 ? family : Color.lerp(hue, family, 0.25)!, darkSurface ? const Color(0xFFFFFFFF) : const Color(0xFF000000),
          darkSurface ? 0.45 : 0.55)!,
  ];
}

/// The effective reading theme: dark when the system is dark (unless the user
/// turned that off), otherwise the chosen theme.
ReadingThemeId effectiveReadingTheme(AppSettings s, Brightness platform) {
  if (s.followSystemDark && platform == Brightness.dark && s.theme != ReadingThemeId.black) {
    return ReadingThemeId.dark;
  }
  return s.theme;
}

/// Font family for a fixed reader font; [ReadingFont.book] resolves per book
/// through `BookType` (typography.dart) and falls back to Literata here.
String? fontFamilyFor(ReadingFont f) => switch (f) {
      ReadingFont.book => 'Literata',
      ReadingFont.literata => 'Literata',
      ReadingFont.atkinson => 'AtkinsonHyperlegible',
      ReadingFont.system => null,
    };

/// The logo red: only the streak flame, the liked heart and badges use it
/// (3.7:1 on white, 5.7:1 on black: enough for icons).
const ember = Color(0xFFFF3131);
