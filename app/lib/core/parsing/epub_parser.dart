import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../models/book.dart';
import 'block_builder.dart';
import 'html_blocks.dart';

class ParseException implements Exception {
  ParseException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ParsedBook {
  const ParsedBook({
    required this.content,
    this.coverBytes,
    this.coverExtension,
    this.isPublicDomain = false,
    this.subjects = const [],
    this.description = '',
  });

  final BookContent content;

  /// `dc:subject` tags (genre hints for the book's typographic voice).
  final List<String> subjects;

  /// `dc:description`, with markup removed.
  final String description;

  /// From `dc:rights`; enables unlimited quote sharing (DESIGN.md §2.6).
  final bool isPublicDomain;
  final Uint8List? coverBytes;
  final String? coverExtension;
}

/// Parses DRM-free EPUB 2/3 files into [BookContent].
class EpubParser {
  const EpubParser();

  ParsedBook parse(Uint8List bytes) {
    final Archive zip;
    try {
      zip = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw ParseException('This file is not a valid EPUB.');
    }
    if (zip.findFile('META-INF/encryption.xml') != null && _isDrm(zip)) {
      throw ParseException('This book is DRM-protected. Cloro can only open DRM-free books.');
    }

    final container = _readText(zip, 'META-INF/container.xml');
    if (container == null) throw ParseException('EPUB is missing META-INF/container.xml.');
    final opfPath = XmlDocument.parse(container)
        .findAllElements('rootfile')
        .map((e) => e.getAttribute('full-path'))
        .whereType<String>()
        .firstOrNull;
    if (opfPath == null) throw ParseException('EPUB has no package document.');
    final opfText = _readText(zip, opfPath);
    if (opfText == null) throw ParseException('EPUB package document not found.');
    final opfDir = p.posix.dirname(opfPath);
    final opf = XmlDocument.parse(opfText);

    String? meta(String local) =>
        opf.descendants.whereType<XmlElement>().where((e) => e.localName == local).map((e) => e.innerText.trim()).where((t) => t.isNotEmpty).firstOrNull;
    final title = meta('title') ?? 'Untitled';
    final author = meta('creator') ?? 'Unknown author';
    final language = meta('language') ?? 'en';
    final rights = (meta('rights') ?? '').toLowerCase();
    final subjects = opf.descendants
        .whereType<XmlElement>()
        .where((e) => e.localName == 'subject')
        .map((e) => e.innerText.trim())
        .where((t) => t.isNotEmpty && t.length < 200)
        .take(20)
        .toList();
    // Descriptions often carry markup; keep the words only.
    final description = (meta('description') ?? '')
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAllMapped(RegExp(r' ([,.;:!?])'), (m) => m[1]!)
        .trim();

    final manifest = <String, _Item>{};
    for (final item in opf.descendants.whereType<XmlElement>().where((e) => e.localName == 'item')) {
      final id = item.getAttribute('id');
      final href = item.getAttribute('href');
      if (id == null || href == null) continue;
      manifest[id] = _Item(
        id: id,
        path: _resolve(opfDir, href),
        mediaType: item.getAttribute('media-type') ?? '',
        properties: item.getAttribute('properties') ?? '',
      );
    }

    final spineEl = opf.descendants.whereType<XmlElement>().where((e) => e.localName == 'spine').firstOrNull;
    if (spineEl == null) throw ParseException('EPUB has no reading order (spine).');
    final spine = <_Item>[];
    for (final ref in spineEl.childElements.where((e) => e.localName == 'itemref')) {
      if (ref.getAttribute('linear') == 'no') continue;
      final item = manifest[ref.getAttribute('idref')];
      if (item != null && !item.properties.contains('nav')) spine.add(item);
    }

    final tocTitles = _tocTitles(zip, manifest, spineEl);

    final chapters = <Chapter>[];
    for (final item in spine) {
      final markup = _readText(zip, item.path);
      if (markup == null) continue;
      final raw = htmlToRawBlocks(markup);
      final words = raw.fold(0, (s, r) => s + countWords(r.text));
      if (words < 20) continue; // cover, title page, blank separators
      final index = chapters.length;
      var blocks = buildBlocks(index, raw);
      final firstHeading = blocks.where((b) => b.type == BlockType.heading).firstOrNull?.text;
      final chapterTitle = tocTitles[item.path] ?? firstHeading ?? 'Section ${index + 1}';
      // The chapter title card shows the title, so drop a duplicate leading heading.
      if (blocks.isNotEmpty &&
          blocks.first.type == BlockType.heading &&
          _norm(blocks.first.text) == _norm(chapterTitle)) {
        blocks = buildBlocks(index, raw.skipWhile((r) => r.type == BlockType.heading && _norm(r.text) == _norm(chapterTitle)).toList());
      }
      if (blocks.isEmpty) continue;
      chapters.add(Chapter(index: index, title: chapterTitle, blocks: blocks));
    }
    if (chapters.isEmpty) throw ParseException('No readable text was found in this EPUB.');

    final cover = _cover(zip, manifest, opf);
    return ParsedBook(
      content: BookContent(title: title, author: author, language: language, chapters: chapters),
      coverBytes: cover?.$1,
      coverExtension: cover?.$2,
      isPublicDomain: rights.contains('public domain'),
      subjects: subjects,
      description: description.length > 600 ? description.substring(0, 600) : description,
    );
  }

  bool _isDrm(Archive zip) {
    final enc = _readText(zip, 'META-INF/encryption.xml') ?? '';
    // Font obfuscation (IDPF/Adobe) is not DRM; anything else encrypting content is.
    final algorithms = RegExp(r'Algorithm="([^"]+)"').allMatches(enc).map((m) => m.group(1)!).toList();
    return algorithms.any((a) => !a.contains('obfuscation') && !a.contains('fontobfuscation'));
  }

  Map<String, String> _tocTitles(Archive zip, Map<String, _Item> manifest, XmlElement spineEl) {
    final titles = <String, String>{};
    final nav = manifest.values.where((i) => i.properties.contains('nav')).firstOrNull;
    if (nav != null) {
      final text = _readText(zip, nav.path);
      if (text != null) {
        final dir = p.posix.dirname(nav.path);
        try {
          final doc = XmlDocument.parse(text);
          for (final a in doc.descendants.whereType<XmlElement>().where((e) => e.localName == 'a')) {
            final href = a.getAttribute('href');
            final label = a.innerText.replaceAll(RegExp(r'\s+'), ' ').trim();
            if (href == null || label.isEmpty) continue;
            titles.putIfAbsent(_resolve(dir, href.split('#').first), () => label);
          }
        } catch (_) {/* fall through to NCX */}
      }
    }
    if (titles.isNotEmpty) return titles;
    final ncxItem = manifest[spineEl.getAttribute('toc')] ??
        manifest.values.where((i) => i.mediaType == 'application/x-dtbncx+xml').firstOrNull;
    if (ncxItem == null) return titles;
    final ncx = _readText(zip, ncxItem.path);
    if (ncx == null) return titles;
    final dir = p.posix.dirname(ncxItem.path);
    for (final point in XmlDocument.parse(ncx).descendants.whereType<XmlElement>().where((e) => e.localName == 'navPoint')) {
      final label = point.descendants.whereType<XmlElement>().where((e) => e.localName == 'text').firstOrNull?.innerText.trim();
      final src = point.descendants.whereType<XmlElement>().where((e) => e.localName == 'content').firstOrNull?.getAttribute('src');
      if (label == null || src == null || label.isEmpty) continue;
      titles.putIfAbsent(_resolve(dir, src.split('#').first), () => label);
    }
    return titles;
  }

  (Uint8List, String)? _cover(Archive zip, Map<String, _Item> manifest, XmlDocument opf) {
    _Item? item = manifest.values.where((i) => i.properties.contains('cover-image')).firstOrNull;
    if (item == null) {
      final coverId = opf.descendants
          .whereType<XmlElement>()
          .where((e) => e.localName == 'meta' && e.getAttribute('name') == 'cover')
          .map((e) => e.getAttribute('content'))
          .firstOrNull;
      item = manifest[coverId];
    }
    if (item == null || !item.mediaType.startsWith('image/')) return null;
    final file = zip.findFile(item.path);
    final bytes = file?.readBytes();
    if (bytes == null) return null;
    return (bytes, p.extension(item.path).replaceFirst('.', ''));
  }

  String? _readText(Archive zip, String path) {
    final file = zip.findFile(path);
    final bytes = file?.readBytes();
    if (bytes == null) return null;
    return utf8.decode(bytes, allowMalformed: true);
  }

  String _resolve(String dir, String href) {
    final decoded = Uri.decodeComponent(href);
    return p.posix.normalize(dir == '.' || dir.isEmpty ? decoded : p.posix.join(dir, decoded));
  }

  String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
}

class _Item {
  const _Item({required this.id, required this.path, required this.mediaType, required this.properties});
  final String id;
  final String path;
  final String mediaType;
  final String properties;
}
