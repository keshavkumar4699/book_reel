import '../models/book.dart';

/// Shared quotes from copyrighted books are limited to a short excerpt with
/// attribution (DESIGN.md §2.6). Public-domain books are not limited.
const maxSharedWordsCopyrighted = 75;

class QuoteExcerpt {
  const QuoteExcerpt(this.text, {required this.truncated});
  final String text;
  final bool truncated;
}

QuoteExcerpt limitQuote(List<String> sentences, {required bool publicDomain, int maxWords = maxSharedWordsCopyrighted}) {
  final all = sentences.join(' ').trim();
  if (publicDomain) return QuoteExcerpt(all, truncated: false);
  final picked = <String>[];
  var words = 0;
  for (final s in sentences) {
    final w = countWords(s);
    if (words + w > maxWords) break;
    picked.add(s);
    words += w;
  }
  if (picked.isNotEmpty) {
    return QuoteExcerpt(picked.join(' '), truncated: picked.length < sentences.length);
  }
  // First sentence alone is too long: cut at a word boundary.
  final tokens = sentences.isEmpty ? <String>[] : sentences.first.split(RegExp(r'\s+'));
  return QuoteExcerpt('${tokens.take(maxWords).join(' ')}…', truncated: true);
}
