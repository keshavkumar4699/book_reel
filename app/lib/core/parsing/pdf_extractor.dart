import 'package:pdfrx/pdfrx.dart';

import '../models/book.dart';
import 'pdf_text_builder.dart';

/// Extracts text from a PDF with PDFium (pdfrx) and rebuilds book structure.
class PdfExtractor {
  const PdfExtractor();

  Future<BookContent> extract(String filePath, {required String fallbackTitle}) async {
    await pdfrxFlutterInitialize();
    final doc = await PdfDocument.openFile(filePath);
    try {
      final pages = <String>[];
      for (final page in doc.pages) {
        final text = await page.loadText();
        pages.add(text?.fullText ?? '');
      }
      final outline = <PdfChapterStart>[];
      try {
        for (final node in await doc.loadOutline()) {
          final page = node.dest?.pageNumber;
          if (page != null && node.title.trim().isNotEmpty) outline.add(PdfChapterStart(page, node.title.trim()));
        }
      } catch (_) {
        // Outline is optional.
      }
      return buildBookFromPdfPages(
        pages,
        title: fallbackTitle,
        author: 'Unknown author',
        outline: outline.length >= 2 ? outline : const [],
      );
    } finally {
      await doc.dispose();
    }
  }
}
