/// Rule-based English sentence splitter.
///
/// Splits after `.`, `!`, `?` or `…` (plus trailing closing quotes/brackets)
/// when followed by whitespace and an uppercase letter, digit or opening quote.
/// Common abbreviations and single-letter initials never end a sentence.
library;

const _abbreviations = {
  'mr', 'mrs', 'ms', 'dr', 'prof', 'sr', 'jr', 'st', 'mt', 'capt', 'col', 'gen', 'lt', 'sgt',
  'rev', 'hon', 'gov', 'pres', 'fig', 'vol', 'ch', 'chap', 'pp', 'no', 'vs', 'cf', 'op', 'ed',
  'jan', 'feb', 'mar', 'apr', 'jun', 'jul', 'aug', 'sep', 'sept', 'oct', 'nov', 'dec',
  'inc', 'ltd', 'co', 'corp', 'dept', 'univ', 'approx', 'est', 'messrs', 'mme', 'mlle',
};

final RegExp _space = RegExp(r'\s+');
final RegExp _opener = RegExp(r'''[\p{Lu}\p{N}"'“‘(\[«¿¡—]''', unicode: true);
final RegExp _closer = RegExp(r'''["'”’)\]»]''');

List<String> splitSentences(String input) {
  final text = input.replaceAll(_space, ' ').trim();
  if (text.isEmpty) return const [];

  final sentences = <String>[];
  var start = 0;
  var i = 0;
  while (i < text.length) {
    final ch = text[i];
    final isTerminal = ch == '.' || ch == '!' || ch == '?' || ch == '…';
    if (!isTerminal) {
      i++;
      continue;
    }
    // Consume runs of terminal punctuation ("?!", "...") and closing quotes.
    var end = i + 1;
    while (end < text.length && (text[end] == '.' || text[end] == '!' || text[end] == '?' || text[end] == '…')) {
      end++;
    }
    while (end < text.length && _closer.hasMatch(text[end])) {
      end++;
    }
    if (end >= text.length) break;
    if (text[end] != ' ' || end + 1 >= text.length || !_opener.hasMatch(text[end + 1])) {
      i = end;
      continue;
    }
    if (ch == '.' && end == i + 1 && _isAbbreviation(text, i)) {
      i = end;
      continue;
    }
    final sentence = text.substring(start, end).trim();
    if (sentence.isNotEmpty) sentences.add(sentence);
    start = end + 1;
    i = start;
  }
  final tail = text.substring(start).trim();
  if (tail.isNotEmpty) sentences.add(tail);
  return sentences;
}

bool _isAbbreviation(String text, int dotIndex) {
  var j = dotIndex - 1;
  while (j >= 0 && RegExp(r'[A-Za-z]').hasMatch(text[j])) {
    j--;
  }
  final word = text.substring(j + 1, dotIndex);
  if (word.isEmpty) return false;
  // Single-letter initials: "J. R. R. Tolkien", "U.S."
  if (word.length == 1 && word.toUpperCase() == word) return true;
  // Dotted acronyms like "e.g." or "U.S.": previous char before the word is a dot.
  if (j >= 0 && text[j] == '.' && word.length <= 2) return true;
  return _abbreviations.contains(word.toLowerCase());
}
