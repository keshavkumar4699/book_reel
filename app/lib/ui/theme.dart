import 'package:flutter/material.dart';

import '../data/settings.dart';

/// Brand accent: warm amber "ember" (UX_DESIGN.md §6.2).
const emberSeed = Color(0xFFD9822B);

/// Reading-surface tokens, separate from the app chrome's colour scheme.
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
  });

  final Color background;
  final Color text;
  final Color muted;
  final Color keyPoint;
  final Color hardWordUnderline;
  final List<Color> highlights;
  final bool isDark;

  static ReadingTheme of(ReadingThemeId id) => switch (id) {
        ReadingThemeId.paper => const ReadingTheme(
            background: Color(0xFFFBF8F1),
            text: Color(0xFF1F1D1A),
            muted: Color(0xFF7A746A),
            keyPoint: Color(0x33E0A84A),
            hardWordUnderline: Color(0xFFB07A2E),
            highlights: _lightHighlights,
            isDark: false,
          ),
        ReadingThemeId.white => const ReadingTheme(
            background: Color(0xFFFFFFFF),
            text: Color(0xFF1A1A1A),
            muted: Color(0xFF6E6E6E),
            keyPoint: Color(0x33E0A84A),
            hardWordUnderline: Color(0xFFB07A2E),
            highlights: _lightHighlights,
            isDark: false,
          ),
        ReadingThemeId.sepia => const ReadingTheme(
            background: Color(0xFFF1E7D0),
            text: Color(0xFF3B2F22),
            muted: Color(0xFF7D6B55),
            keyPoint: Color(0x40D69A3C),
            hardWordUnderline: Color(0xFF9A6526),
            highlights: _lightHighlights,
            isDark: false,
          ),
        ReadingThemeId.dark => const ReadingTheme(
            background: Color(0xFF141414),
            text: Color(0xFFE6E1D6),
            muted: Color(0xFF9A948A),
            keyPoint: Color(0x33E0A84A),
            hardWordUnderline: Color(0xFFE0A84A),
            highlights: _darkHighlights,
            isDark: true,
          ),
        ReadingThemeId.black => const ReadingTheme(
            background: Color(0xFF000000),
            text: Color(0xFFDCD7CC),
            muted: Color(0xFF8E897F),
            keyPoint: Color(0x2EE0A84A),
            hardWordUnderline: Color(0xFFE0A84A),
            highlights: _darkHighlights,
            isDark: true,
          ),
      };

  static const _lightHighlights = [Color(0x40F2B84B), Color(0x4067C587), Color(0x405B9BE6), Color(0x40E87AA4)];
  static const _darkHighlights = [Color(0x40F2B84B), Color(0x4067C587), Color(0x405B9BE6), Color(0x40E87AA4)];

  @override
  ReadingTheme copyWith() => this;

  @override
  ReadingTheme lerp(ThemeExtension<ReadingTheme>? other, double t) => t < 0.5 ? this : (other as ReadingTheme? ?? this);
}

/// The effective reading theme: dark when the system is dark (unless the user
/// turned that off), otherwise the chosen theme.
ReadingThemeId effectiveReadingTheme(AppSettings s, Brightness platform) {
  if (s.followSystemDark && platform == Brightness.dark && s.theme != ReadingThemeId.black) {
    return ReadingThemeId.dark;
  }
  return s.theme;
}

String? fontFamilyFor(ReadingFont f) => switch (f) {
      ReadingFont.literata => 'Literata',
      ReadingFont.atkinson => 'AtkinsonHyperlegible',
      ReadingFont.system => null,
    };

ThemeData buildAppTheme({required Brightness brightness}) {
  final scheme = ColorScheme.fromSeed(seedColor: emberSeed, brightness: brightness);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    navigationBarTheme: NavigationBarThemeData(
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      backgroundColor: scheme.surfaceContainer,
    ),
    bottomSheetTheme: const BottomSheetThemeData(showDragHandle: true),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}

/// Accent used for the streak flame and goal progress regardless of the
/// dynamic colour scheme.
const ember = Color(0xFFE08A2E);
