import 'package:book_reel/core/text/sentence_splitter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('splits on terminal punctuation followed by a capital', () {
    expect(splitSentences('It rained. We stayed in! Did you? Yes.'),
        ['It rained.', 'We stayed in!', 'Did you?', 'Yes.']);
  });

  test('keeps abbreviations, initials and decimals together', () {
    expect(splitSentences('Mr. Smith met Dr. Jones at 3.5 p.m. on Monday. J. R. R. Tolkien wrote it.'),
        ['Mr. Smith met Dr. Jones at 3.5 p.m. on Monday.', 'J. R. R. Tolkien wrote it.']);
  });

  test('handles closing quotes and ellipses', () {
    expect(splitSentences('“Stop!” she cried. He waited… Then he left.'),
        ['“Stop!” she cried.', 'He waited…', 'Then he left.']);
  });

  test('does not split before lowercase continuation', () {
    expect(splitSentences('Use tools, e.g. hammers and saws. Done.'), ['Use tools, e.g. hammers and saws.', 'Done.']);
  });

  test('normalises whitespace and handles empty input', () {
    expect(splitSentences('  One.\n\n  Two.  '), ['One.', 'Two.']);
    expect(splitSentences('   '), isEmpty);
  });
}
