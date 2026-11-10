import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:book_reel/core/models/book.dart';
import 'package:book_reel/core/parsing/epub_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses the bundled starter EPUB', () {
    final bytes = File('assets/books/alice.epub').readAsBytesSync();
    final book = const EpubParser().parse(bytes).content;
    expect(book.title, "Alice's Adventures in Wonderland");
    expect(book.author, 'Lewis Carroll');
    expect(book.chapters, hasLength(11));
    expect(book.chapters.first.title, 'CHAPTER I. Down the Rabbit-Hole');
    // The duplicate <h2> chapter heading is dropped; text starts with the first paragraph.
    expect(book.chapters.first.blocks.first.sentences.first.text, startsWith('Alice was beginning'));
    expect(book.wordCount, greaterThan(25000));
    // Verse is kept as a quote block with one line per sentence.
    final quotes = book.chapters.expand((c) => c.blocks).where((b) => b.type == BlockType.quote);
    expect(quotes, isNotEmpty);
    // Sentence IDs are stable and well-formed.
    final s = book.chapters[2].blocks[3].sentences.first;
    expect(s.id, 'c2.b3.s0');
  });

  test('round-trips through JSON', () {
    final bytes = File('assets/books/alice.epub').readAsBytesSync();
    final book = const EpubParser().parse(bytes).content;
    final copy = BookContent.fromJson(book.toJson());
    expect(copy.chapters.length, book.chapters.length);
    expect(copy.chapters[5].blocks[2].text, book.chapters[5].blocks[2].text);
  });

  test('reads genre tags and the description from the package metadata', () {
    const opf = '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:title>The Quiet Case</dc:title><dc:creator>A. Writer</dc:creator><dc:language>en</dc:language>
<dc:subject>Detective and mystery stories</dc:subject><dc:subject>  </dc:subject><dc:subject>England -- Fiction</dc:subject>
<dc:description>&lt;p&gt;A village, a &lt;b&gt;body&lt;/b&gt;,   and no witnesses.&lt;/p&gt;</dc:description>
</metadata>
<manifest><item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/></manifest>
<spine><itemref idref="c1"/></spine>
</package>''';
    final archive = Archive()
      ..addFile(ArchiveFile.string('mimetype', 'application/epub+zip'))
      ..addFile(ArchiveFile.string('META-INF/container.xml',
          '<container><rootfiles><rootfile full-path="content.opf"/></rootfiles></container>'))
      ..addFile(ArchiveFile.string('content.opf', opf))
      ..addFile(ArchiveFile.string('c1.xhtml',
          '<html><body><h1>One</h1><p>The inspector arrived at dawn. Nobody in the village would speak to him, '
              'and the only inn had closed its shutters before he had even crossed the bridge into the square.</p></body></html>'));
    final parsed = const EpubParser().parse(Uint8List.fromList(ZipEncoder().encode(archive)));
    expect(parsed.subjects, ['Detective and mystery stories', 'England -- Fiction']);
    expect(parsed.description, 'A village, a body, and no witnesses.');
    // The starter book carries no tags.
    expect(const EpubParser().parse(File('assets/books/alice.epub').readAsBytesSync()).subjects, isEmpty);
  });

  test('rejects non-EPUB data and DRM-encrypted books', () {
    expect(() => const EpubParser().parse(Uint8List.fromList([1, 2, 3])), throwsA(isA<ParseException>()));

    final archive = Archive()
      ..addFile(ArchiveFile.string('mimetype', 'application/epub+zip'))
      ..addFile(ArchiveFile.string('META-INF/encryption.xml',
          '<encryption><EncryptedData><EncryptionMethod Algorithm="http://www.w3.org/2001/04/xmlenc#aes128-cbc"/></EncryptedData></encryption>'));
    final drm = Uint8List.fromList(ZipEncoder().encode(archive));
    expect(() => const EpubParser().parse(drm),
        throwsA(isA<ParseException>().having((e) => e.message, 'message', contains('DRM'))));
  });
}
