import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/settings.dart';
import 'theme.dart';

/// Bundled font families and their names. All are unmodified Google Fonts
/// under the SIL Open Font License; each ships its licence text as
/// `assets/fonts/OFL-<family>.txt`.
const bundledFonts = <String, String>{
  'Literata': 'Literata',
  'AtkinsonHyperlegible': 'Atkinson Hyperlegible',
  'DMSerifDisplay': 'DM Serif Display',
  'Lora': 'Lora',
  'PlayfairDisplay': 'Playfair Display',
  'Alegreya': 'Alegreya',
  'Cinzel': 'Cinzel',
  'Exo2': 'Exo 2',
  'Orbitron': 'Orbitron',
  'LibreBaskerville': 'Libre Baskerville',
  'Oswald': 'Oswald',
  'Outfit': 'Outfit',
  'Nunito': 'Nunito',
  'Fredoka': 'Fredoka',
};

/// Adds the font licences to the app's licences page (Settings → About).
void registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final font in bundledFonts.entries) {
      yield LicenseEntryWithLineBreaks(['${font.value} (font)'], await rootBundle.loadString('assets/fonts/OFL-${font.key}.txt'));
    }
  });
}

/// The typographic "voice" of a book: a body face for reading and a display
/// face for spotlight lines and chapter titles, matched to what the book is
/// (UX_DESIGN.md Revision 4). Chosen per book by the AI on paid tiers and by
/// [classifyVoice] on the device.
enum BookVoice { classic, romance, fantasy, scifi, suspense, modern, playful }

class VoiceStyle {
  const VoiceStyle({
    required this.label,
    required this.description,
    required this.body,
    required this.display,
    this.bodyScale = 1,
    this.bodyHeight = 1.5,
    this.bodyWeight = FontWeight.w400,
    this.displayWeight = FontWeight.w600,
    this.displayStyle = FontStyle.normal,
    this.displayLetterSpacing = 0,
    this.displayHeight = 1.18,
    this.displayScale = 1,
  });

  final String label;
  final String description;

  /// Font family for reading text.
  final String body;

  /// Font family for spotlight lines and chapter titles.
  final String display;

  /// Size compensation so every body face reads at the same apparent size
  /// (x-heights differ between faces).
  final double bodyScale;
  final double bodyHeight;
  final FontWeight bodyWeight;
  final FontWeight displayWeight;
  final FontStyle displayStyle;
  final double displayLetterSpacing;
  final double displayHeight;
  final double displayScale;
}

const voiceStyles = <BookVoice, VoiceStyle>{
  // Literary and general fiction, classics, essays, history, poetry.
  BookVoice.classic: VoiceStyle(
    label: 'Classic',
    description: 'Literata with DM Serif Display, for literary fiction and classics',
    body: 'Literata',
    display: 'DMSerifDisplay',
    displayWeight: FontWeight.w400,
    displayHeight: 1.14,
    displayScale: 1.04,
  ),
  // Romance, love stories, lyrical memoir.
  BookVoice.romance: VoiceStyle(
    label: 'Romantic',
    description: 'Lora with Playfair Display italic, for love stories',
    body: 'Lora',
    display: 'PlayfairDisplay',
    bodyScale: 1.02,
    displayWeight: FontWeight.w500,
    displayStyle: FontStyle.italic,
    displayHeight: 1.16,
    displayScale: 1.04,
  ),
  // Fantasy, myth, legend, fairy tales, epic adventure.
  BookVoice.fantasy: VoiceStyle(
    label: 'Fantasy',
    description: 'Alegreya with Cinzel, for myth and magic',
    body: 'Alegreya',
    display: 'Cinzel',
    bodyScale: 1.08,
    displayWeight: FontWeight.w600,
    displayLetterSpacing: 0.6,
    displayHeight: 1.22,
    displayScale: 0.9,
  ),
  // Science fiction, space, cyberpunk, technology.
  BookVoice.scifi: VoiceStyle(
    label: 'Sci-fi',
    description: 'Exo 2 with Orbitron, for the future',
    body: 'Exo2',
    display: 'Orbitron',
    bodyScale: 0.98,
    displayWeight: FontWeight.w600,
    displayLetterSpacing: 0.4,
    displayHeight: 1.28,
    displayScale: 0.82,
  ),
  // Mystery, thriller, crime, horror, suspense.
  BookVoice.suspense: VoiceStyle(
    label: 'Suspense',
    description: 'Libre Baskerville with Oswald, for mystery and thrillers',
    body: 'LibreBaskerville',
    display: 'Oswald',
    bodyScale: 0.9,
    bodyHeight: 1.55,
    displayWeight: FontWeight.w500,
    displayLetterSpacing: 0.3,
    displayHeight: 1.18,
    displayScale: 1.02,
  ),
  // Non-fiction: self-help, business, science, productivity, psychology.
  BookVoice.modern: VoiceStyle(
    label: 'Modern',
    description: 'Atkinson Hyperlegible with Outfit, for non-fiction',
    body: 'AtkinsonHyperlegible',
    display: 'Outfit',
    displayWeight: FontWeight.w700,
    displayHeight: 1.12,
  ),
  // Children's books, humour, light reads.
  BookVoice.playful: VoiceStyle(
    label: 'Playful',
    description: 'Nunito with Fredoka, for young readers and humour',
    body: 'Nunito',
    display: 'Fredoka',
    bodyScale: 1.02,
    bodyWeight: FontWeight.w500,
    displayWeight: FontWeight.w600,
    displayHeight: 1.14,
    displayScale: 1.02,
  ),
};

BookVoice voiceByName(String? name, {BookVoice fallback = BookVoice.classic}) =>
    BookVoice.values.where((v) => v.name == name).firstOrNull ?? fallback;

/// Resolved fonts for one book and the reader's settings: the book's own
/// voice unless the reader picked a specific font (e.g. Atkinson Hyperlegible
/// for low vision), which then applies everywhere.
class BookType {
  const BookType(this.voice, this.settings);

  final BookVoice voice;
  final AppSettings settings;

  VoiceStyle get style => voiceStyles[voice]!;
  bool get usesVoice => settings.font == ReadingFont.book;

  String? get bodyFamily => usesVoice ? style.body : fontFamilyFor(settings.font);
  String? get displayFamily => usesVoice ? style.display : fontFamilyFor(settings.font);

  /// Body text style at the reader's size.
  TextStyle body({required Color color, double scale = 1, List<Shadow>? shadows}) => TextStyle(
        fontFamily: bodyFamily,
        fontSize: settings.fontSize * scale * (usesVoice ? style.bodyScale : 1),
        fontWeight: usesVoice ? style.bodyWeight : FontWeight.w400,
        height: usesVoice ? style.bodyHeight : settings.lineHeight.clamp(1.4, 1.7),
        letterSpacing: settings.letterSpacing,
        wordSpacing: settings.wordSpacing,
        color: color,
        shadows: shadows,
      );

  /// Display style (spotlights, chapter titles) at [size].
  TextStyle display({required Color color, required double size, List<Shadow>? shadows}) => TextStyle(
        fontFamily: displayFamily,
        fontSize: size * (usesVoice ? style.displayScale : 1),
        fontWeight: usesVoice ? style.displayWeight : FontWeight.w700,
        fontStyle: usesVoice ? style.displayStyle : FontStyle.normal,
        letterSpacing: usesVoice ? style.displayLetterSpacing : -0.2,
        height: usesVoice ? style.displayHeight : 1.16,
        color: color,
        shadows: shadows,
      );
}
