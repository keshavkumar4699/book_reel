import 'package:book_reel/core/models/book.dart';
import 'package:book_reel/core/parsing/epub_parser.dart' show ParseException;
import 'package:book_reel/core/parsing/pdf_text_builder.dart';
import 'package:flutter_test/flutter_test.dart';

String page(int n, List<String> body) => ['THE BOOK OF HABITS', ...body, '$n'].join('\n');

void main() {
  final filler = 'This line of body text is long enough to look like a normal printed line of';
  test('removes running heads and page numbers, de-hyphenates and finds chapters', () {
    final pages = [
      page(1, ['CHAPTER 1', '', '$filler prose that contin-', 'ues on the next line and ends here.', '', 'A second para-', 'graph is short.']),
      page(2, ['$filler text that runs off the', 'bottom of the page and keeps going']),
      page(3, ['into the next page before ending.', '', 'CHAPTER 2', '', 'The second chapter begins with a sentence of reasonable length for testing.', 'It has two lines and ends right here.']),
      page(4, ['$filler more filler words so that this chapter has enough text to be kept.', 'Final line.']),
    ];
    final book = buildBookFromPdfPages(pages, title: 'Habits', author: 'A');
    expect(book.chapters.map((c) => c.title), ['CHAPTER 1', 'CHAPTER 2']);
    final text = book.chapters.first.blocks.map((b) => b.text).join('\n');
    expect(text, isNot(contains('THE BOOK OF HABITS')));
    expect(text, contains('continues on the next line'));
    expect(text, contains('A second paragraph is short.'));
    expect(text, contains('runs off the bottom of the page and keeps going into the next page before ending.'));
    expect(book.chapters.first.blocks.every((b) => b.type != BlockType.heading || b.text != '1'), isTrue);
  });

  test('uses the PDF outline for chapter boundaries when available', () {
    final pages = [
      for (var i = 1; i <= 4; i++) page(i, ['$filler page $i content that is plain prose.', 'It ends here.']),
    ];
    final book = buildBookFromPdfPages(pages, title: 'T', author: 'A', outline: const [
      PdfChapterStart(1, 'Intro'),
      PdfChapterStart(3, 'Main part'),
    ]);
    expect(book.chapters.map((c) => c.title), ['Intro', 'Main part']);
  });

  test('rejects scanned PDFs', () {
    expect(() => buildBookFromPdfPages(['', '', ' ', 'some text here that is long enough'], title: 'T', author: 'A'),
        throwsA(isA<ParseException>().having((e) => e.message, 'm', contains('scanned'))));
  });
}
