import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:book_reel/core/models/book.dart';
import 'package:book_reel/core/models/front_matter.dart';
import 'package:book_reel/core/parsing/epub_parser.dart';
import 'package:flutter_test/flutter_test.dart';

Chapter ch(int i, String title, List<String> paragraphs) => Chapter(index: i, title: title, blocks: [
      for (final (b, t) in paragraphs.indexed)
        Block(index: b, type: BlockType.paragraph, sentences: [Sentence(id: 'c$i.b$b.s0', text: t)]),
    ]);

final prose = List.filled(30, 'She walked along the quiet river and thought about the long summer that had passed.');

void main() {
  test('skips the title page, copyright, contents and dedication; opens at the introduction', () {
    final chapters = [
      ch(0, 'Title Page', ['The Long River', 'A Novel', 'by A. Writer']),
      ch(1, 'Copyright', ['Copyright © 2021 A. Writer. All rights reserved.', 'ISBN 978-0-00-000000-0', 'Printed in India.']),
      ch(2, 'Contents', ['Introduction', 'Chapter 1. Spring', 'Chapter 2. Summer', 'Chapter 3. Autumn', 'Chapter 4. Winter', 'Notes']),
      ch(3, 'Dedication', ['For my mother.']),
      ch(4, 'Introduction', prose),
      ch(5, 'Chapter 1. Spring', prose),
      ch(6, 'Chapter 2. Summer', prose),
      ch(7, 'Chapter 3. Autumn', prose),
      ch(8, 'Chapter 4. Winter', prose),
      ch(9, 'Notes', prose),
    ];
    expect(findBodyStart(chapters), 4);
    expect([for (final c in chapters) isFrontMatter(c)], [true, true, true, true, false, false, false, false, false, false]);
  });

  test('front matter is found by its content when the title says nothing', () {
    expect(isFrontMatter(ch(0, 'Section 1', ['Copyright © 1999. All rights reserved.', 'First published 1999.'])), isTrue,
        reason: 'a "Section" title is normally the body, but…');
    expect(isFrontMatter(ch(0, 'The Project Gutenberg eBook of Walden', ['This ebook is for the use of anyone anywhere.'])), isTrue);
    expect(isFrontMatter(ch(0, 'Opening', ['The Garden', 'Morning', 'Noon', 'Evening', 'Night', 'Dawn', 'Rain', 'Snow'])), isTrue,
        reason: 'a contents page: short lines only');
    expect(isFrontMatter(ch(0, 'Opening', prose)), isFalse, reason: 'prose is the book');
    expect(isFrontMatter(ch(0, 'IV. The Trial', ['short'])), isFalse, reason: 'a Roman-numeral chapter');
    expect(isFrontMatter(ch(0, 'Prologue', ['Copyright is mentioned here, but this is the story.'])), isFalse);
  });

  test("the publisher's mark wins, keeping a preface just before it; never more than half the book is skipped", () {
    final chapters = [
      ch(0, 'Half title', ['The Long River']),
      ch(1, 'Preface', prose),
      ch(2, 'Chapter 1', prose),
      ch(3, 'Chapter 2', prose),
      ch(4, 'Chapter 3', prose),
    ];
    expect(findBodyStart(chapters, marked: 2), 1, reason: 'the preface before the marked chapter is kept');
    expect(findBodyStart(chapters, marked: 4), 1, reason: 'a mark past half the book is ignored');
    final allFront = [for (var i = 0; i < 6; i++) ch(i, 'Copyright', ['© 2020'])];
    expect(findBodyStart(allFront), 3, reason: 'at most half');
    expect(findBodyStart([ch(0, 'Copyright', ['© 2020'])]), 0);
  });

  test('books saved before this work out where they start; new ones keep it', () {
    final book = BookContent(title: 't', author: 'a', chapters: [
      ch(0, 'Copyright', ['Copyright © 2021. All rights reserved.']),
      ch(1, 'Chapter 1', prose),
    ], bodyStart: 1);
    final json = book.toJson();
    expect(BookContent.fromJson(json).bodyStart, 1);
    json.remove('start');
    expect(BookContent.fromJson(json).bodyStart, 1, reason: 'computed for older saved books');
    final alice = const EpubParser().parse(File('assets/books/alice.epub').readAsBytesSync()).content;
    expect(alice.bodyStart, 0, reason: 'the starter book begins at Chapter I');
  });

  Uint8List epub({required String nav, String guide = ''}) {
    const container = '<?xml version="1.0"?><container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">'
        '<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>';
    final opf = '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Marked</dc:title><dc:creator>A</dc:creator></metadata>
<manifest>
<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
<item id="t" href="title.xhtml" media-type="application/xhtml+xml"/>
<item id="a" href="about.xhtml" media-type="application/xhtml+xml"/>
<item id="c1" href="text/c1.xhtml" media-type="application/xhtml+xml"/>
<item id="c2" href="text/c2.xhtml" media-type="application/xhtml+xml"/>
<item id="c3" href="text/c3.xhtml" media-type="application/xhtml+xml"/>
</manifest>
<spine><itemref idref="t"/><itemref idref="a"/><itemref idref="c1"/><itemref idref="c2"/><itemref idref="c3"/></spine>
$guide
</package>''';
    String page(String h, String p) => '<html xmlns="http://www.w3.org/1999/xhtml"><body><h1>$h</h1><p>$p</p></body></html>';
    final words = prose.join(' ');
    final archive = Archive()
      ..addFile(ArchiveFile.string('mimetype', 'application/epub+zip'))
      ..addFile(ArchiveFile.string('META-INF/container.xml', container))
      ..addFile(ArchiveFile.string('OEBPS/content.opf', opf))
      ..addFile(ArchiveFile.string('OEBPS/nav.xhtml', nav))
      // Plain titles the classifier can't place: only the mark tells.
      ..addFile(ArchiveFile.string('OEBPS/title.xhtml', page('The Long River', words)))
      ..addFile(ArchiveFile.string('OEBPS/about.xhtml', page('About the River', words)))
      ..addFile(ArchiveFile.string('OEBPS/text/c1.xhtml', page('Spring', words)))
      ..addFile(ArchiveFile.string('OEBPS/text/c2.xhtml', page('Summer', words)))
      ..addFile(ArchiveFile.string('OEBPS/text/c3.xhtml', page('Autumn', words)));
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  test('EPUB 3 bodymatter landmark and EPUB 2 guide reference set where the book opens', () {
    const landmarks = '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><body>'
        '<nav epub:type="toc"><ol><li><a href="text/c1.xhtml">Spring</a></li></ol></nav>'
        '<nav epub:type="landmarks"><ol><li><a epub:type="toc" href="nav.xhtml">Contents</a></li>'
        '<li><a epub:type="bodymatter" href="text/c1.xhtml#start">Start</a></li></ol></nav></body></html>';
    final withLandmark = const EpubParser().parse(epub(nav: landmarks)).content;
    expect(withLandmark.chapters[withLandmark.bodyStart].title, 'Spring');

    const plainNav = '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><body>'
        '<nav epub:type="toc"><ol><li><a href="text/c1.xhtml">Spring</a></li></ol></nav></body></html>';
    final withGuide = const EpubParser()
        .parse(epub(nav: plainNav, guide: '<guide><reference type="text" title="Start" href="text/c1.xhtml"/></guide>'))
        .content;
    expect(withGuide.chapters[withGuide.bodyStart].title, 'Spring');

    final unmarked = const EpubParser().parse(epub(nav: plainNav)).content;
    expect(unmarked.bodyStart, 0, reason: 'no mark and nothing that looks like front matter');
  });
}
