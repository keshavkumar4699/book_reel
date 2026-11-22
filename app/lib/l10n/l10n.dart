import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';
import 'package:intl/date_symbol_data_local.dart' show initializeDateFormatting;
import 'package:intl/intl.dart' show DateFormat, Intl;

/// A language the app is translated into.
@immutable
class AppLanguage {
  const AppLanguage(this.code, this.name, this.english);

  /// ISO 639-1, as in `assets/l10n/<code>.json`.
  final String code;

  /// Its own name, as its readers write it.
  final String name;
  final String english;

  bool get rtl => code == 'ar';
  Locale get locale => Locale(code);
}

/// English and the eight most-spoken languages after it (first and second
/// language speakers together): Mandarin Chinese, Hindi, Spanish, Arabic,
/// French, Bengali, Portuguese and Russian.
const appLanguages = [
  AppLanguage('en', 'English', 'English'),
  AppLanguage('zh', '中文（简体）', 'Chinese'),
  AppLanguage('hi', 'हिन्दी', 'Hindi'),
  AppLanguage('es', 'Español', 'Spanish'),
  AppLanguage('ar', 'العربية', 'Arabic'),
  AppLanguage('fr', 'Français', 'French'),
  AppLanguage('bn', 'বাংলা', 'Bengali'),
  AppLanguage('pt', 'Português', 'Portuguese'),
  AppLanguage('ru', 'Русский', 'Russian'),
];

AppLanguage languageFor(String code) => appLanguages.firstWhere((l) => l.code == code, orElse: () => appLanguages.first);

/// The language to show: the one chosen in Settings, else the phone's first
/// language the app has, else English.
String resolveLanguage(String chosen, Iterable<Locale> phone) {
  if (appLanguages.any((l) => l.code == chosen)) return chosen;
  for (final l in phone) {
    if (appLanguages.any((a) => a.code == l.languageCode)) return l.languageCode;
  }
  return 'en';
}

/// The app's text in one language. The English text in the code is the key:
/// a string without a translation shows in English. A value is a string, or
/// for counts a map of plural forms (`zero`, `one`, `two`, `few`, `many`,
/// `other`) chosen by the language's own rules.
class Strings {
  Strings(this.code, this._table);

  /// The language on screen (set before the app builds with it).
  static Strings current = Strings('en', const {});

  final String code;
  final Map<String, Object?> _table;

  bool get isEmpty => _table.isEmpty;

  /// `assets/l10n/<code>.json` (nothing to load for English).
  static Future<Strings> load(String code) async {
    if (code == 'en') return Strings('en', const {});
    try {
      return Strings(code, (jsonDecode(await rootBundle.loadString('assets/l10n/$code.json')) as Map).cast<String, Object?>());
    } catch (_) {
      return Strings('en', const {});
    }
  }

  String tr(String english, [Map<String, Object?> args = const {}]) {
    final value = _table[english];
    final text = value is Map ? value['other'] : value;
    return fill(text is String && text.isNotEmpty ? text : english, args);
  }

  String plural(int n, String one, String other, [Map<String, Object?> args = const {}]) {
    final value = _table[other];
    String form;
    if (value is Map) {
      String? f(String k) => value[k] as String?;
      form = Intl.pluralLogic(n, locale: code, zero: f('zero'), one: f('one'), two: f('two'), few: f('few'), many: f('many'), other: f('other') ?? other);
    } else if (value is String && value.isNotEmpty) {
      form = value;
    } else {
      form = n == 1 ? one : other;
    }
    return fill(form, {'n': n, ...args});
  }

  /// Puts each `{name}` in [text] in place.
  static String fill(String text, Map<String, Object?> args) {
    if (args.isEmpty || !text.contains('{')) return text;
    return text.replaceAllMapped(RegExp(r'\{(\w+)\}'), (m) => args.containsKey(m[1]) ? '${args[m[1]]}' : m[0]!);
  }
}

/// [english] in the language on screen, with each `{name}` from [args].
String tr(String english, [Map<String, Object?> args = const {}]) => Strings.current.tr(english, args);

/// A count: [one] or [other] in English (each with `{n}`), the language's
/// own plural forms otherwise (keyed by [other]).
String trn(int n, String one, String other, [Map<String, Object?> args = const {}]) => Strings.current.plural(n, one, other, args);

/// Marks text shown later through [tr] (a label kept in a list or a const),
/// so the translation check finds it. Returns [english] as it is.
String tk(String english) => english;

/// Every element rebuilds, keeping its state: after the language changes,
/// all text (which reads [Strings.current]) is drawn again.
void rebuildAllText(BuildContext context) {
  void mark(Element e) {
    e.markNeedsBuild();
    e.visitChildren(mark);
  }

  (context as Element).visitChildren(mark);
}

bool _datesReady = false;

/// Dates in the app's language ([pattern] as in `DateFormat`): day and
/// month names come from the language's own data, bundled with the app.
DateFormat localDate(String pattern) {
  if (!_datesReady) {
    _datesReady = true;
    // Loads the bundled data at once (the Future is only for the API).
    initializeDateFormatting();
  }
  // The app's English is British: "2 Oct", not "Oct 2".
  final code = Strings.current.code;
  return DateFormat(pattern, code == 'en' ? 'en_GB' : code);
}
