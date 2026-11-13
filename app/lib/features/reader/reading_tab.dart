import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/book.dart';
import '../../data/library.dart';
import '../../ui/kit.dart';
import 'reader_screen.dart';

/// The Reading tab (Cloro plan §6): the reels of the book you're reading.
/// Opening a book anywhere in the app switches here (`/reading?book=…`);
/// without one, it shows the book read last. There is no close button:
/// switching tabs leaves the book where it is.
class ReadingTab extends ConsumerWidget {
  const ReadingTab({super.key, this.bookId, this.startSid});

  final String? bookId;
  final String? startSid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final books = ref.watch(libraryProvider);
    final id = bookId ?? _lastRead(books)?.id;
    if (id == null) {
      final kit = Kit.of(context);
      return Scaffold(
        backgroundColor: kit.base,
        body: Center(
          child: KitEmpty(
            emoji: '📖',
            title: 'Nothing to read yet',
            message: 'Pick a book from your Library and it opens here.',
            action: KitButton(label: 'Open Library', onPressed: () => context.go('/library')),
          ),
        ),
      );
    }
    // A new book (or a jump to a passage) starts a fresh reader.
    return ReaderScreen(key: ValueKey('$id|${startSid ?? ''}'), bookId: id, startSid: startSid, embedded: true);
  }

  static BookMeta? _lastRead(List<BookMeta> books) {
    if (books.isEmpty) return null;
    final read = [for (final b in books) if (b.lastReadAt != null) b]..sort((a, b) => b.lastReadAt!.compareTo(a.lastReadAt!));
    return read.isNotEmpty ? read.first : books.first;
  }
}
