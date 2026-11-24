import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/book.dart';
import '../data/library.dart';
import '../data/store_provider.dart';

/// A book file in the folder, as Android lists it.
@immutable
class FolderBook {
  const FolderBook({required this.id, required this.name, required this.size, required this.modified});

  factory FolderBook.fromMap(Map<Object?, Object?> m) => FolderBook(
        id: '${m['id']}',
        name: '${m['name']}',
        size: (m['size'] as num?)?.toInt() ?? 0,
        modified: (m['modified'] as num?)?.toInt() ?? 0,
      );

  final String id;
  final String name;
  final int size;
  final int modified;

  /// Changes when the file does (a new copy under the same name, say).
  String get signature => '$size:$modified';
}

/// The folder books are imported from by themselves.
@immutable
class BooksFolderState {
  const BooksFolderState({
    this.uri,
    this.name,
    this.scanning = false,
    this.lastScan,
    this.lastAdded = const [],
    this.unavailable = false,
    this.hintHidden = false,
  });

  /// The folder, as Android names it for this app; null when none is chosen.
  final String? uri;

  /// Its name as shown ("Books").
  final String? name;

  /// Looking for new books (and importing them) right now.
  final bool scanning;
  final DateTime? lastScan;

  /// The titles the last look added to the Library.
  final List<String> lastAdded;

  /// The folder can't be read any more: moved, deleted, or its access taken
  /// back in the phone's settings. Choosing it again fixes it.
  final bool unavailable;

  /// The Library's suggestion to pick a folder was put away.
  final bool hintHidden;

  bool get chosen => uri != null;

  BooksFolderState copyWith({bool? scanning, DateTime? lastScan, List<String>? lastAdded, bool? unavailable, bool? hintHidden}) =>
      BooksFolderState(
        uri: uri,
        name: name,
        scanning: scanning ?? this.scanning,
        lastScan: lastScan ?? this.lastScan,
        lastAdded: lastAdded ?? this.lastAdded,
        unavailable: unavailable ?? this.unavailable,
        hintHidden: hintHidden ?? this.hintHidden,
      );
}

/// Every EPUB and PDF put in a folder you pick (say Download/Books) shows up
/// in the Library by itself: looked for as the app opens or comes back, as
/// the Library opens, and when you pull it down. Android's folder picker
/// gives the app that folder alone (android/…/BooksFolder.kt).
///
/// Each file is read once: one removed from the Library isn't brought back
/// unless the file itself changes. Importing a file by hand still works as
/// before.
class BooksFolderNotifier extends Notifier<BooksFolderState> {
  static const channel = MethodChannel('app.cloro/books_folder');

  /// Files larger than this are left alone (a scanned PDF of hundreds of MB).
  static const maxBytes = 150 * 1024 * 1024;

  /// Looks taken on their own (the app opening or coming back) are at least
  /// this far apart.
  static const every = Duration(minutes: 1);

  /// The files read so far, by id: their signature then (imported, or found
  /// to be no book Cloro can open).
  Map<String, String> _seen = {};

  @override
  BooksFolderState build() {
    final doc = ref.read(storeProvider).doc('books_folder');
    _seen = {for (final e in ((doc?['seen'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'};
    return BooksFolderState(uri: doc?['uri'] as String?, name: doc?['name'] as String?, hintHidden: doc?['hintHidden'] == true);
  }

  void _save() => ref
      .read(storeProvider)
      .saveDoc('books_folder', {'uri': state.uri, 'name': state.name, 'seen': _seen, 'hintHidden': state.hintHidden});

  /// Puts away the Library's suggestion to pick a folder (Settings still has it).
  void hideHint() {
    state = state.copyWith(hintHidden: true);
    _save();
  }

  /// Android's folder picker; the books in the folder are imported straight
  /// away. Null when none was chosen (or the phone has no picker).
  Future<List<BookMeta>?> choose() async {
    Map<String, dynamic>? picked;
    try {
      picked = await channel.invokeMapMethod<String, dynamic>('pick');
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('Books folder: ${e.code} ${e.message}');
      return null;
    }
    final uri = picked?['uri'] as String?;
    if (uri == null || !ref.mounted) return null;
    final before = state.uri;
    if (before != null && before != uri) unawaited(_release(before));
    // Another folder: everything in it is new.
    if (before != uri) _seen = {};
    state = BooksFolderState(uri: uri, name: (picked!['name'] as String?) ?? '', hintHidden: state.hintHidden);
    _save();
    return scan(force: true);
  }

  /// Stops importing from the folder; the books already imported stay.
  Future<void> forget() async {
    final uri = state.uri;
    _seen = {};
    state = BooksFolderState(hintHidden: state.hintHidden);
    _save();
    if (uri != null) await _release(uri);
  }

  Future<void> _release(String uri) async {
    try {
      await channel.invokeMethod<void>('release', {'uri': uri});
    } on MissingPluginException {
      // Not on Android.
    } on PlatformException {
      // Already gone.
    }
  }

  /// Imports the books put in the folder since the last look, and returns
  /// them. [force]: now, however recent the last look.
  Future<List<BookMeta>> scan({bool force = false}) async {
    final uri = state.uri;
    if (uri == null || state.scanning) return const [];
    final last = state.lastScan;
    if (!force && last != null && DateTime.now().difference(last) < every) return const [];
    state = state.copyWith(scanning: true);
    final added = <BookMeta>[];
    var unavailable = false;
    try {
      final listed = await channel.invokeListMethod<Object?>('list', {'uri': uri}) ?? const [];
      final files = [for (final m in listed) FolderBook.fromMap(m! as Map<Object?, Object?>)];
      for (final f in files) {
        if (!ref.mounted || state.uri != uri) return added;
        if (_seen[f.id] == f.signature) continue;
        if (f.size <= maxBytes) {
          final book = await _import(uri, f);
          if (book != null) added.add(book);
        }
        _seen[f.id] = f.signature;
        _save();
      }
      // A file taken out of the folder is forgotten: put back, it's new again.
      final ids = {for (final f in files) f.id};
      _seen.removeWhere((id, _) => !ids.contains(id));
      _save();
    } on PlatformException catch (e) {
      unavailable = e.code == 'denied';
      debugPrint('Books folder: ${e.code} ${e.message}');
    } on MissingPluginException {
      // Not on Android.
    }
    if (ref.mounted && state.uri == uri) {
      state = state.copyWith(scanning: false, lastScan: DateTime.now(), lastAdded: [for (final b in added) b.title], unavailable: unavailable);
    }
    return added;
  }

  /// One file into the Library: the book, when it's new to it.
  Future<BookMeta?> _import(String uri, FolderBook f) async {
    String? path;
    try {
      path = await channel.invokeMethod<String>('copy', {'uri': uri, 'id': f.id});
      if (path == null) return null;
      final bytes = await File(path).readAsBytes();
      final library = ref.read(libraryProvider.notifier);
      final had = {for (final b in ref.read(libraryProvider)) b.id};
      final book = await library.importBytes(bytes, f.name);
      return had.contains(book.id) ? null : book;
    } on PlatformException catch (e) {
      // The whole folder gone: stop looking (see [scan]); one unreadable file: skip it.
      if (e.code == 'denied') rethrow;
      debugPrint('Books folder: ${f.name}: ${e.message}');
      return null;
    } catch (e) {
      // Not a book Cloro can open (DRM, a scanned PDF): left alone until it changes.
      debugPrint('Books folder: ${f.name}: $e');
      return null;
    } finally {
      if (path != null) {
        try {
          File(path).deleteSync();
        } on FileSystemException {
          // Already gone.
        }
      }
    }
  }
}

final booksFolderProvider = NotifierProvider<BooksFolderNotifier, BooksFolderState>(BooksFolderNotifier.new);
