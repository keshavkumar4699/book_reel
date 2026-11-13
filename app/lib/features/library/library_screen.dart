import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/book.dart';
import '../../core/parsing/epub_parser.dart' show ParseException;
import '../../data/library.dart';
import '../../ui/kit.dart';
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
      if (mounted) context.go('/read/${meta.id}');
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
    showKitDialog<void>(context, title: 'Can’t open this book', message: message, actions: const [KitDialogAction('OK', primary: true)]);
  }

  Future<void> _bookMenu(BookMeta book) async {
    final action = await showKitActions<String>(
      context,
      title: book.title,
      subtitle: '${book.author} · ${book.chapterCount} chapters · ${book.wordCount} words',
      actions: const [
        KitAction('read', 'Read', icon: Icons.play_arrow_rounded),
        KitAction('restart', 'Start from the beginning', icon: Icons.restart_alt_rounded),
        KitAction('remove', 'Remove from library', icon: Icons.delete_outline_rounded, destructive: true),
      ],
    );
    if (!mounted) return;
    switch (action) {
      case 'read':
        context.go('/read/${book.id}');
      case 'restart':
        context.go('/read/${book.id}?sid=c0.b0.s0');
      case 'remove':
        final ok = await showKitConfirm(
          context,
          title: 'Remove book?',
          message: 'Your highlights and saved cards stay in your Notebook.',
          confirm: 'Remove',
          destructive: true,
        );
        if (ok) await ref.read(libraryProvider.notifier).remove(book.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    final books = ref.watch(libraryProvider);
    return KitPage(
      back: false,
      backdrop: false,
      dock: true,
      title: 'Library',
      actions: [
        KitButton(
          label: _importing ? 'Preparing…' : 'Import',
          icon: _importing ? null : Icons.add_rounded,
          leading: _importing ? const SizedBox(width: 18, height: 18, child: KitSpinner(size: 18)) : null,
          compact: true,
          onPressed: _importing ? null : _import,
        ),
      ],
      slivers: [
        if (books.isEmpty)
          SliverToBoxAdapter(
            child: KitEmpty(
              emoji: '📚',
              title: 'Your library is empty',
              message: 'Import a DRM-free EPUB or a PDF with selectable text.',
              action: KitButton.secondary(
                label: 'Add a free classic',
                onPressed: () => ref.read(libraryProvider.notifier).ensureStarterBook(),
              ),
            ),
          )
        else
          SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 180,
              mainAxisSpacing: 20,
              crossAxisSpacing: 16,
              childAspectRatio: 0.5,
            ),
            itemCount: books.length,
            itemBuilder: (context, i) {
              final b = books[i];
              return KitPressable(
                onTap: () => context.go('/read/${b.id}'),
                onLongPress: () => _bookMenu(b),
                pressedScale: 0.97,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  LayoutBuilder(builder: (context, c) => BookCover(book: b, width: c.maxWidth)),
                  const SizedBox(height: 8),
                  KitProgress(value: b.progress, height: 4),
                  const SizedBox(height: 6),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(b.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: kit.strong.copyWith(fontSize: 14, height: 1.2)),
                        Text(
                          b.finishedAt != null ? 'Finished ✓' : '${(b.progress * 100).round()}% · ${b.author}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: kit.caption.copyWith(fontSize: 12.5),
                        ),
                      ]),
                    ),
                    KitPressable(
                      onTap: () => _bookMenu(b),
                      semanticLabel: 'More for ${b.title}',
                      excludeSemantics: true,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(6, 0, 0, 6),
                        child: Icon(Icons.more_vert_rounded, size: 20, color: kit.inkSoft),
                      ),
                    ),
                  ]),
                ]),
              );
            },
          ),
      ],
    );
  }
}
