import 'dart:convert';
import 'dart:io';

import 'package:book_reel/l10n/l10n.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

final _lit = RegExp(r"""r?'(?:\\.|[^'\\\n])*'|r?"(?:\\.|[^"\\\n])*\"""");

String _unquote(String group) {
  final out = StringBuffer();
  for (final m in _lit.allMatches(group)) {
    var s = m[0]!;
    final raw = s.startsWith('r');
    s = raw ? s.substring(2, s.length - 1) : s.substring(1, s.length - 1);
    if (!raw) {
      s = s.replaceAllMapped(RegExp(r'\\u([0-9a-fA-F]{4})|\\(.)'), (e) {
        if (e[1] != null) return String.fromCharCode(int.parse(e[1]!, radix: 16));
        return switch (e[2]) { 'n' => '\n', 't' => '\t', _ => e[2]! };
      });
    }
    out.write(s);
  }
  return out.toString();
}

/// Every text the app shows through tr/trn/tk, and lib/l10n/keys.dart.
Map<String, String?> appKeys() {
  const lits = r"""(?:(?:r?'(?:\\.|[^'\\\n])*'|r?"(?:\\.|[^"\\\n])*")\s*)+""";
  final keys = <String, String?>{};
  for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
    final src = f.readAsStringSync();
    if (f.path.endsWith('l10n${Platform.pathSeparator}l10n.dart')) continue;
    if (f.path.endsWith('l10n${Platform.pathSeparator}keys.dart')) {
      for (final m in _lit.allMatches(src.substring(src.indexOf('[')))) {
        keys.putIfAbsent(_unquote(m[0]!), () => null);
      }
      continue;
    }
    for (final m in RegExp(r'\b(?:tr|tk)\(\s*(' + lits + r')\s*[,)]').allMatches(src)) {
      keys.putIfAbsent(_unquote(m[1]!), () => null);
    }
    for (final m in RegExp(r'\btrn\(\s*[^,]+?,\s*(' + lits + r')\s*,\s*(' + lits + r')\s*[,)]').allMatches(src)) {
      keys[_unquote(m[2]!)] = _unquote(m[1]!);
    }
  }
  return keys;
}

Set<String> _holes(String s) => {for (final m in RegExp(r'\{(\w+)\}').allMatches(s)) m[1]!};

void main() {
  final keys = appKeys();

  test('the app has text to translate, and every language has all of it', () {
    expect(keys.length, greaterThan(600));
    for (final l in appLanguages.where((l) => l.code != 'en')) {
      final file = File('assets/l10n/${l.code}.json');
      expect(file.existsSync(), isTrue, reason: '${l.english}: assets/l10n/${l.code}.json');
      final table = (jsonDecode(file.readAsStringSync()) as Map).cast<String, Object?>();
      final missing = [for (final k in keys.keys) if (!table.containsKey(k)) k];
      expect(missing, isEmpty, reason: '${l.english} is missing ${missing.length}: ${missing.take(10).join(' | ')}');
      for (final MapEntry(:key, :value) in table.entries) {
        if (!keys.containsKey(key)) continue; // left from text the app no longer shows
        final forms = value is Map ? value.cast<String, Object?>() : {'other': value};
        expect(forms['other'], isA<String>(), reason: '${l.english}: "$key" needs an "other" form');
        for (final MapEntry(key: form, value: text) in forms.entries) {
          expect(text, isA<String>());
          expect((text as String).trim(), isNotEmpty, reason: '${l.english}: "$key" ($form) is empty');
          // The same {placeholders} (a "one" form may leave out the count).
          final want = _holes(form == 'one' || form == 'zero' || form == 'two' ? keys[key] ?? key : key);
          final have = _holes(text);
          expect(have.difference(_holes(key)), isEmpty, reason: '${l.english}: "$key" ($form) has unknown placeholders $have');
          if (form == 'other') expect(have, want, reason: '${l.english}: "$key" must keep its placeholders');
        }
      }
    }
  });

  test('a plural key is never also used as plain text by mistake', () {
    final plurals = {for (final e in keys.entries) if (e.value != null) e.key};
    for (final l in appLanguages.where((l) => l.code != 'en')) {
      final table = (jsonDecode(File('assets/l10n/${l.code}.json').readAsStringSync()) as Map).cast<String, Object?>();
      for (final k in plurals) {
        final v = table[k];
        if (v is Map) expect(v.keys.every((f) => const {'zero', 'one', 'two', 'few', 'many', 'other'}.contains(f)), isTrue, reason: '$k in ${l.code}');
      }
    }
  });

  test('text fills in its placeholders, and counts follow each language’s plural rules', () {
    final ru = Strings('ru', {
      '{n} books': {'one': '{n} книга', 'few': '{n} книги', 'many': '{n} книг', 'other': '{n} книги'},
      'Hello, {name}': 'Привет, {name}',
    });
    expect(ru.plural(1, '{n} book', '{n} books'), '1 книга');
    expect(ru.plural(3, '{n} book', '{n} books'), '3 книги');
    expect(ru.plural(5, '{n} book', '{n} books'), '5 книг');
    expect(ru.plural(21, '{n} book', '{n} books'), '21 книга');
    expect(ru.tr('Hello, {name}', {'name': 'Asha'}), 'Привет, Asha');
    expect(ru.tr('{n} books'), '{n} книги', reason: 'a plural key read as plain text gives its "other" form');
    expect(ru.tr('Not translated'), 'Not translated', reason: 'falls back to English');
    final en = Strings('en', const {});
    expect(en.plural(1, '{n} book', '{n} books'), '1 book');
    expect(en.plural(0, '{n} book', '{n} books'), '0 books');
  });

  test('the language: the reader’s choice, else the phone’s, else English', () {
    expect(resolveLanguage('es', const [Locale('fr')]), 'es');
    expect(resolveLanguage('', const [Locale('de'), Locale('hi', 'IN')]), 'hi');
    expect(resolveLanguage('', const [Locale('de')]), 'en');
    expect(resolveLanguage('xx', const [Locale('pt', 'BR')]), 'pt');
    expect(languageFor('ar').rtl, isTrue);
    expect(appLanguages.map((l) => l.code), ['en', 'zh', 'hi', 'es', 'ar', 'fr', 'bn', 'pt', 'ru']);
  });
}
