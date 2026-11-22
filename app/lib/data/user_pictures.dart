import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Pictures you add from your phone to read on. Each is copied into the
/// app's own storage (the original can be moved or deleted), named by when
/// it was added and its own name, and listed newest first. JPG, PNG, WebP
/// and GIF; an animated GIF or WebP plays on a loop.
class UserPictures {
  UserPictures._();

  /// Tests replace this.
  static Future<Directory> Function() root = getApplicationDocumentsDirectory;

  static final _picture = RegExp(r'\.(jpe?g|png|webp|gif)$', caseSensitive: false);

  static Future<Directory> _dir() async {
    final dir = Directory('${(await root()).path}/backgrounds');
    await dir.create(recursive: true);
    return dir;
  }

  /// Your pictures' paths, newest first.
  static Future<List<String>> list() async {
    try {
      final dir = await _dir();
      final files = [
        for (final f in dir.listSync().whereType<File>())
          if (_picture.hasMatch(f.path)) f,
      ];
      // Named to sort newest first (see [add]).
      files.sort((a, b) => a.path.split('/').last.compareTo(b.path.split('/').last));
      return [for (final f in files) f.path];
    } catch (e) {
      debugPrint('Your pictures unavailable: $e');
      return const [];
    }
  }

  /// Adds [pictures] (each its file name and bytes); returns the paths of
  /// those that open as pictures, in the order given. Others are left out.
  static Future<List<String>> add(List<({String name, Uint8List bytes})> pictures) async {
    final dir = await _dir();
    final added = <String>[];
    final stamp = DateTime.now().millisecondsSinceEpoch;
    for (final (i, p) in pictures.indexed) {
      if (!await opens(p.bytes)) continue;
      final ext = _picture.firstMatch(p.name)?.group(1)?.toLowerCase() ?? 'jpg';
      final base = p.name.replaceFirst(_picture, '').replaceAll(RegExp(r'[^\w\- ]+'), '').trim();
      // Named to sort newest first: the time counts down, then the order picked.
      final order = '${(9999999999999 - stamp).toString().padLeft(13, '0')}${i.toString().padLeft(3, '0')}';
      final file = File('${dir.path}/$order-${base.isEmpty ? 'picture' : base}.$ext');
      await file.writeAsBytes(p.bytes, flush: true);
      added.add(file.path);
    }
    return added;
  }

  /// Removes one of your pictures (not the original on the phone).
  static Future<void> remove(String path) async {
    try {
      await File(path).delete();
    } catch (_) {}
  }

  /// The picture's name as you gave it (its file "…-beach_day.jpg" → "Beach day").
  static String labelOf(String path) {
    final name = path.split('/').last.replaceFirst(_picture, '').replaceFirst(RegExp(r'^\d{16}-'), '');
    final words = name.replaceAll(RegExp(r'[_\-]+'), ' ').trim();
    return words.isEmpty ? '' : words[0].toUpperCase() + words.substring(1);
  }

  /// Whether [bytes] decode as a picture this phone can show.
  static Future<bool> opens(Uint8List bytes) async {
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final ok = descriptor.width > 0 && descriptor.height > 0;
      descriptor.dispose();
      buffer.dispose();
      return ok;
    } catch (_) {
      return false;
    }
  }
}
