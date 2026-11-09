import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/book.dart';
import '../../core/parsing/epub_parser.dart' show ParseException;
import '../../data/library.dart';
import '../../ui/widgets.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  bool _importing = false;

  Future<void> _import() async {
    final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['epub', 'pdf']);
    if (files.isEmpty || !mounted) return;
    setState(() => _importing = true);
    try {
      final file = files.first;
      final meta = await ref.read(libraryProvider.notifier).importBytes(await file.readAsBytes(), file.name);
      if (mounted) context.push('/read/${meta.id}');
    } on ParseException catch (e) {
      _error(e.message);
    } catch (e) {
      _error('Could not import this file. ($e)');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _error(String message) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Can’t open this book'),
        content: Text(message),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
      ),
    );
  }

  Future<void> _bookMenu(BookMeta book) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(book.title), subtitle: Text('${book.author} · ${book.chapterCount} chapters · ${book.wordCount} words')),
          ListTile(leading: const Icon(Icons.play_arrow), title: const Text('Read'), onTap: () => Navigator.pop(context, 'read')),
          ListTile(leading: const Icon(Icons.restart_alt), title: const Text('Start from the beginning'), onTap: () => Navigator.pop(context, 'restart')),
          ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Remove from library'), onTap: () => Navigator.pop(context, 'remove')),
        ]),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'read':
        context.push('/read/${book.id}');
      case 'restart':
        context.push('/read/${book.id}?sid=c0.b0.s0');
      case 'remove':
        final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Remove book?'),
            content: const Text('Your highlights and saved cards stay in your Notebook.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
            ],
          ),
        );
        if (ok == true) await ref.read(libraryProvider.notifier).remove(book.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final books = ref.watch(libraryProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Library')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _importing ? null : _import,
        icon: _importing
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.add),
        label: Text(_importing ? 'Preparing reels…' : 'Import book'),
      ),
      body: books.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.auto_stories_outlined, size: 64),
                  const SizedBox(height: 16),
                  Text('Your library is empty', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  const Text('Import a DRM-free EPUB or a PDF with selectable text.', textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: () => ref.read(libraryProvider.notifier).ensureStarterBook(),
                    child: const Text('Add a free classic'),
                  ),
                ]),
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 180,
                mainAxisSpacing: 20,
                crossAxisSpacing: 16,
                childAspectRatio: 0.52,
              ),
              itemCount: books.length,
              itemBuilder: (context, i) {
                final b = books[i];
                return InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => context.push('/read/${b.id}'),
                  onLongPress: () => _bookMenu(b),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    LayoutBuilder(builder: (context, c) => BookCover(book: b, width: c.maxWidth)),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: b.progress, borderRadius: BorderRadius.circular(4)),
                    const SizedBox(height: 6),
                    Text(b.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                    Text(
                      b.finishedAt != null ? 'Finished ✓' : '${(b.progress * 100).round()}% · ${b.author}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ]),
                );
              },
            ),
    );
  }
}
