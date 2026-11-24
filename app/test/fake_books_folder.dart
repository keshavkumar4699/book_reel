import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A small EPUB with its own title (so its own bytes, and its own book).
Uint8List epubNamed(String title) {
  final opf = '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>$title</dc:title><dc:creator>A. Writer</dc:creator><dc:language>en</dc:language></metadata>
<manifest><item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/></manifest>
<spine><itemref idref="c1"/></spine>
</package>''';
  final archive = Archive()
    ..addFile(ArchiveFile.string('mimetype', 'application/epub+zip'))
    ..addFile(ArchiveFile.string('META-INF/container.xml', '<container><rootfiles><rootfile full-path="content.opf"/></rootfiles></container>'))
    ..addFile(ArchiveFile.string('content.opf', opf))
    ..addFile(ArchiveFile.string(
        'c1.xhtml',
        '<html><body><h1>One</h1><p>$title begins on a quiet morning. Nobody in the village would speak of it, '
            'and the only inn had closed its shutters before the traveller had even crossed the bridge.</p></body></html>'));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// The folder on the "phone": files by id, as Android's picker would list them.
class FakeFolderPhone {
  FakeFolderPhone(this.dir);
  final Directory dir;
  final files = <String, ({String name, int size, int modified, Uint8List bytes})>{};
  final calls = <String>[];
  String folder = 'content://com.android.externalstorage.documents/tree/primary%3ADownload%2FBooks';
  bool readable = true;
  bool picks = true;

  void put(String id, String name, Uint8List bytes, {int modified = 1}) =>
      files[id] = (name: name, size: bytes.length, modified: modified, bytes: bytes);

  Future<Object?> handle(MethodCall call) async {
    calls.add(call.method);
    final args = (call.arguments as Map?)?.cast<String, Object?>();
    switch (call.method) {
      case 'pick':
        return picks ? {'uri': folder, 'name': 'Books'} : null;
      case 'list':
        expect(args!['uri'], folder);
        if (!readable) throw PlatformException(code: 'denied', message: 'gone');
        return [for (final e in files.entries) {'id': e.key, 'name': e.value.name, 'size': e.value.size, 'modified': e.value.modified}];
      case 'copy':
        final f = files[args!['id']]!;
        final out = File('${dir.path}/copy-${calls.length}.book')..writeAsBytesSync(f.bytes);
        return out.path;
      case 'release':
        return null;
    }
    throw MissingPluginException();
  }

  int count(String method) => calls.where((c) => c == method).length;
}
