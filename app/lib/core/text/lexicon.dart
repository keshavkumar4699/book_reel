/// Word frequency + offline dictionary used for hard-word detection and the
/// word sheet (DESIGN.md §2.5).
// Private fields keep the public constructor names readable.
// ignore_for_file: prefer_initializing_formals
library;

enum ReadingLevel {
  beginner(3.8),
  intermediate(3.2),
  advanced(2.6);

  const ReadingLevel(this.zipfThreshold);

  /// Words with a Zipf frequency below this are treated as "hard".
  final double zipfThreshold;
}

class DictionarySense {
  const DictionarySense({required this.partOfSpeech, required this.definition, this.example});
  final String partOfSpeech;
  final String definition;
  final String? example;
}

class DictionaryEntry {
  const DictionaryEntry({required this.lemma, required this.senses});
  final String lemma;
  final List<DictionarySense> senses;
}

final RegExp _tokenRe = RegExp(r"[A-Za-z][A-Za-z'’\-]*[A-Za-z]|[A-Za-z]");

class Lexicon {
  Lexicon({required Map<String, double> zipf, required Map<String, List<List<String>>> dictionary})
      : _zipf = zipf,
        _dict = dictionary;

  /// Parses the bundled asset formats (TSV `word\tzipf` and WordNet JSON).
  factory Lexicon.fromAssets({required String zipfTsv, required Map<String, dynamic> dictionaryJson}) {
    final zipf = <String, double>{};
    for (final line in zipfTsv.split('\n')) {
      final tab = line.indexOf('\t');
      if (tab <= 0) continue;
      zipf[line.substring(0, tab)] = double.tryParse(line.substring(tab + 1)) ?? 0;
    }
    final dict = dictionaryJson.map((k, v) =>
        MapEntry(k, (v as List).map((s) => (s as List).cast<String>()).toList()));
    return Lexicon(zipf: zipf, dictionary: dict);
  }

  final Map<String, double> _zipf;
  final Map<String, List<List<String>>> _dict;

  static final empty = Lexicon(zipf: const {}, dictionary: const {});

  bool get isEmpty => _zipf.isEmpty && _dict.isEmpty;

  double? zipf(String word) => _zipf[_normalize(word)];

  /// Returns base-form candidates (WordNet "morphy"-style suffix rules).
  static List<String> lemmaCandidates(String word) {
    final w = _normalize(word);
    final out = <String>[w];
    void add(String s) {
      if (s.length >= 2 && !out.contains(s)) out.add(s);
    }

    if (w.endsWith('ies')) add('${w.substring(0, w.length - 3)}y');
    if (w.endsWith('es')) add(w.substring(0, w.length - 2));
    if (w.endsWith('s') && !w.endsWith('ss')) add(w.substring(0, w.length - 1));
    if (w.endsWith('ied')) add('${w.substring(0, w.length - 3)}y');
    if (w.endsWith('ed')) {
      add(w.substring(0, w.length - 2));
      add(w.substring(0, w.length - 1));
      if (w.length > 4 && w[w.length - 3] == w[w.length - 4]) add(w.substring(0, w.length - 3));
    }
    if (w.endsWith('ing')) {
      add(w.substring(0, w.length - 3));
      add('${w.substring(0, w.length - 3)}e');
      if (w.length > 5 && w[w.length - 4] == w[w.length - 5]) add(w.substring(0, w.length - 4));
    }
    if (w.endsWith('er')) add(w.substring(0, w.length - 2));
    if (w.endsWith('est')) add(w.substring(0, w.length - 3));
    if (w.endsWith('ly')) add(w.substring(0, w.length - 2));
    return out;
  }

  DictionaryEntry? lookup(String word) {
    for (final candidate in lemmaCandidates(word)) {
      final senses = _dict[candidate];
      if (senses != null) {
        return DictionaryEntry(
          lemma: candidate,
          senses: [
            for (final s in senses)
              DictionarySense(partOfSpeech: s[0], definition: s[1], example: s.length > 2 ? s[2] : null),
          ],
        );
      }
    }
    return null;
  }

  /// Finds hard words in [sentence]. Skips proper nouns (capitalised words
  /// that are not sentence-initial, or unknown capitalised words) and words
  /// the lexicon doesn't know at all (names, typos).
  List<String> hardWords(String sentence, ReadingLevel level) {
    final result = <String>[];
    final seen = <String>{};
    var first = true;
    for (final m in _tokenRe.allMatches(sentence)) {
      final token = m.group(0)!;
      final isFirst = first;
      first = false;
      if (token.length < 4) continue;
      final capitalised = token[0] != token[0].toLowerCase();
      if (capitalised && !isFirst) continue;
      final lower = _normalize(token);
      if (seen.contains(lower)) continue;
      final z = _zipf[lower];
      final known = z != null || lookup(lower) != null;
      if (!known) continue;
      if (capitalised && z == null) continue;
      if ((z ?? 0) < level.zipfThreshold && lookup(lower) != null) {
        result.add(token);
        seen.add(lower);
      }
    }
    return result;
  }

  static String _normalize(String w) => w.toLowerCase().replaceAll('’', "'");
}
