import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Offline-first local storage.
///
/// Small documents (settings, library index, notebook, habit data) are loaded
/// into memory once at startup so reads are synchronous; writes are atomic
/// (write temp file, then rename) and serialised per document. Large blobs
/// (parsed books, segment maps) are read on demand.
///
/// Kept behind this small interface so it can be swapped for SQLite (Drift)
/// when cloud sync lands (IMPLEMENTATION_PLAN.md Phase 7).
class JsonStore {
  JsonStore._(this.root, this._docs);

  final Directory root;
  final Map<String, Object?> _docs;
  final Map<String, Future<void>> _pending = {};

  static const _docNames = ['settings', 'library', 'notebook', 'habit', 'device'];

  static Future<JsonStore> open(Directory root) async {
    await root.create(recursive: true);
    await Directory('${root.path}/books').create(recursive: true);
    final docs = <String, Object?>{};
    for (final name in _docNames) {
      final f = File('${root.path}/$name.json');
      if (await f.exists()) {
        try {
          docs[name] = jsonDecode(await f.readAsString());
        } catch (_) {
          docs[name] = null; // corrupt file: start fresh rather than crash
        }
      }
    }
    return JsonStore._(root, docs);
  }

  Map<String, dynamic>? doc(String name) => _docs[name] as Map<String, dynamic>?;

  Future<void> saveDoc(String name, Map<String, dynamic> value) {
    _docs[name] = value;
    return _write('${root.path}/$name.json', jsonEncode(value), name);
  }

  String blobPath(String name) => '${root.path}/books/$name';

  Future<String?> readBlob(String name) async {
    final f = File(blobPath(name));
    return await f.exists() ? f.readAsString() : null;
  }

  Future<void> writeBlob(String name, String contents) => _write(blobPath(name), contents, 'blob:$name');

  Future<void> writeBytes(String name, List<int> bytes) async {
    final f = File(blobPath(name));
    await f.writeAsBytes(bytes, flush: true);
  }

  Future<void> deleteBlobsWithPrefix(String prefix) async {
    final dir = Directory('${root.path}/books');
    await for (final e in dir.list()) {
      if (e is File && e.uri.pathSegments.last.startsWith(prefix)) await e.delete();
    }
  }

  Future<void> _write(String path, String contents, String key) {
    final previous = _pending[key] ?? Future<void>.value();
    final next = previous.then((_) async {
      final tmp = File('$path.tmp');
      await tmp.writeAsString(contents, flush: true);
      await tmp.rename(path);
    });
    _pending[key] = next.whenComplete(() {
      if (identical(_pending[key], next)) _pending.remove(key);
    });
    return next;
  }

  /// Waits for all pending writes (used by tests and before app exit).
  Future<void> flush() => Future.wait(_pending.values.toList());
}
