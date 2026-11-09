import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/book.dart';
import '../core/parsing/epub_parser.dart';
import '../core/parsing/pdf_extractor.dart';
import 'store_provider.dart';

const starterBookAsset = 'assets/books/alice.epub';

class LibraryNotifier extends Notifier<List<BookMeta>> {
  @override
  List<BookMeta> build() {
    final json = ref.read(storeProvider).doc('library');
    final books = ((json?['books'] as List?) ?? const [])
        .map((e) => BookMeta.fromJson(e as Map<String, dynamic>))
        .toList();
    return _sorted(books);
  }

  List<BookMeta> _sorted(List<BookMeta> books) => [...books]
    ..sort((a, b) => (b.lastReadAt ?? b.addedAt).compareTo(a.lastReadAt ?? a.addedAt));

  void _set(List<BookMeta> books) {
    state = _sorted(books);
    ref.read(storeProvider).saveDoc('library', {'books': state.map((b) => b.toJson()).toList()});
  }

  BookMeta? byId(String id) => state.where((b) => b.id == id).firstOrNull;

  /// The most recently read unfinished book, for "Continue reading".
  BookMeta? get current =>
      state.where((b) => b.finishedAt == null && b.lastReadAt != null).firstOrNull ??
      state.where((b) => b.finishedAt == null).firstOrNull;

  /// Imports the bundled public-domain starter book on first launch.
  Future<BookMeta?> ensureStarterBook() async {
    final store = ref.read(storeProvider);
    if (store.doc('library')?['starterImported'] == true) return null;
    final data = await rootBundle.load(starterBookAsset);
    final meta = await importBytes(data.buffer.asUint8List(), 'alice.epub');
    await store.saveDoc('library', {
      'books': state.map((b) => b.toJson()).toList(),
      'starterImported': true,
    });
    return meta;
  }

  /// Imports an EPUB or text PDF. Returns the existing entry for duplicates.
  Future<BookMeta> importBytes(Uint8List bytes, String fileName) async {
    final store = ref.read(storeProvider);
    final id = sha256.convert(bytes).toString();
    final existing = byId(id);
    if (existing != null) return existing;

    final lower = fileName.toLowerCase();
    BookContent content;
    BookFormat format;
    var publicDomain = false;
    String? coverPath;
    if (lower.endsWith('.epub')) {
      format = BookFormat.epub;
      final parsed = await compute(_parseEpub, bytes);
      content = parsed.content;
      publicDomain = parsed.isPublicDomain;
      if (parsed.coverBytes != null) {
        final name = '$id.cover.${parsed.coverExtension ?? 'jpg'}';
        await store.writeBytes(name, parsed.coverBytes!);
        coverPath = store.blobPath(name);
      }
    } else if (lower.endsWith('.pdf')) {
      format = BookFormat.pdf;
      final path = store.blobPath('$id.pdf');
      await File(path).writeAsBytes(bytes, flush: true);
      content = await const PdfExtractor().extract(path, fallbackTitle: _titleFromFileName(fileName));
    } else {
      throw ParseException('BookReel supports EPUB and PDF files.');
    }

    await store.writeBlob('$id.content.json', await compute(_encode, content));
    final meta = BookMeta(
      id: id,
      title: content.title,
      author: content.author,
      format: format,
      addedAt: DateTime.now(),
      wordCount: content.wordCount,
      chapterCount: content.chapters.length,
      isPublicDomain: publicDomain,
      coverPath: coverPath,
    );
    _set([...state, meta]);
    return meta;
  }

  void updatePosition(String bookId, {required String sid, required double progress}) {
    final b = byId(bookId);
    if (b == null) return;
    _set([
      for (final x in state)
        x.id == bookId ? x.copyWith(positionSid: sid, progress: progress, lastReadAt: DateTime.now()) : x,
    ]);
  }

  /// Marks a book finished; returns true the first time.
  bool markFinished(String bookId) {
    final b = byId(bookId);
    if (b == null || b.finishedAt != null) return false;
    _set([for (final x in state) x.id == bookId ? x.copyWith(finishedAt: DateTime.now(), progress: 1) : x]);
    return true;
  }

  Future<void> remove(String bookId) async {
    _set(state.where((b) => b.id != bookId).toList());
    await ref.read(storeProvider).deleteBlobsWithPrefix(bookId);
  }
}

ParsedBook _parseEpub(Uint8List bytes) => const EpubParser().parse(bytes);

String _encode(BookContent c) => jsonEncode(c.toJson());

BookContent _decode(String s) => BookContent.fromJson(jsonDecode(s) as Map<String, dynamic>);

String _titleFromFileName(String name) {
  final base = name.replaceAll(RegExp(r'\.[^.]+$'), '').replaceAll(RegExp(r'[_\-]+'), ' ').trim();
  return base.isEmpty ? 'Untitled' : base[0].toUpperCase() + base.substring(1);
}

final libraryProvider = NotifierProvider<LibraryNotifier, List<BookMeta>>(LibraryNotifier.new);

final bookContentProvider = FutureProvider.family<BookContent, String>((ref, bookId) async {
  final raw = await ref.read(storeProvider).readBlob('$bookId.content.json');
  if (raw == null) throw StateError('Book content missing for $bookId');
  return compute(_decode, raw);
});

/// Words before [sid] divided by total words.
double progressAt(BookContent book, String sid) {
  final target = parseSid(sid);
  if (target == null || book.wordCount == 0) return 0;
  var before = 0;
  for (final c in book.chapters) {
    if (c.index < target.chapter) {
      before += c.wordCount;
      continue;
    }
    if (c.index > target.chapter) break;
    for (final s in c.sentences) {
      if (s.id == sid) return before / book.wordCount;
      before += s.wordCount;
    }
  }
  return (before / book.wordCount).clamp(0, 1).toDouble();
}
