import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/book.dart';
import '../../core/parsing/epub_parser.dart' show ParseException;
import '../../data/library.dart';
import '../../services/books_folder.dart';
import '../../ui/kit.dart';
import '../../ui/widgets.dart';
import '../../l10n/l10n.dart';
import 'books_folder_sheet.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    // New books in your books folder, if you chose one (at most once a minute).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(booksFolderProvider.notifier).scan();
    });
  }

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
      _error(tr('Could not import this file. ({error})', {'error': e}));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _error(String message) {
    if (!mounted) return;
    showKitDialog<void>(context, title: tr('Can’t open this book'), message: message, actions: [KitDialogAction(tr('OK'), primary: true)]);
  }

  Future<void> _bookMenu(BookMeta book) async {
    final action = await showKitActions<String>(
      context,
      title: book.title,
      subtitle: '${book.author} · ${trn(book.chapterCount, '{n} chapter', '{n} chapters')} · ${tr('{count} words', {'count': book.wordCount})}',
      actions: [
        KitAction('read', tr('Read'), icon: Icons.play_arrow_rounded),
        KitAction('restart', tr('Start from the beginning'), icon: Icons.restart_alt_rounded),
        KitAction('remove', tr('Remove from library'), icon: Icons.delete_outline_rounded, destructive: true),
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
          title: tr('Remove book?'),
          message: tr('Your highlights and saved cards stay in your Notebook.'),
          confirm: tr('Remove'),
          destructive: true,
        );
        if (ok) await ref.read(libraryProvider.notifier).remove(book.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    final books = ref.watch(libraryProvider);
    final folder = ref.watch(booksFolderProvider);
    final folderName = folder.name == null || folder.name!.isEmpty ? tr('your books folder') : folder.name!;
    // Books the folder brought in while the Library is open (opening the app, coming back to it).
    ref.listen<BooksFolderState>(booksFolderProvider, (before, now) {
      if (before?.scanning == true && !now.scanning && now.lastAdded.isNotEmpty) {
        showKitToast(context, trn(now.lastAdded.length, 'Added {n} book from {folder}', 'Added {n} books from {folder}', {'folder': folderName}), emoji: '📚');
      }
    });
    return KitPage(
      back: false,
      backdrop: false,
      dock: true,
      title: tr('Library'),
      // Where new books come from by themselves, once a folder is chosen.
      subtitle: !folder.chosen
          ? null
          : folder.unavailable
              ? tr('Can’t read {folder}. Choose it again.', {'folder': folderName})
              : folder.scanning
                  ? tr('Looking for new books in {folder}…', {'folder': folderName})
                  : tr('New books in {folder} appear here by themselves', {'folder': folderName}),
      onRefresh: folder.chosen
          ? () async {
              final added = await ref.read(booksFolderProvider.notifier).scan(force: true);
              if (context.mounted) reportBooksFolder(context, ref.read(booksFolderProvider), added);
            }
          : null,
      actions: [
        KitIconButton(
          icon: folder.chosen ? (folder.unavailable ? Icons.folder_off_outlined : Icons.folder_rounded) : Icons.create_new_folder_outlined,
          semanticLabel: tr('Books folder'),
          color: folder.unavailable ? kit.danger : null,
          onPressed: () => showBooksFolder(context, ref),
        ),
        KitButton(
          label: _importing ? tr('Preparing…') : tr('Import'),
          icon: _importing ? null : Icons.add_rounded,
          leading: _importing ? const SizedBox(width: 18, height: 18, child: KitSpinner(size: 18)) : null,
          compact: true,
          onPressed: _importing ? null : _import,
        ),
      ],
      slivers: [
        // Until a folder is chosen: the way to have books arrive by themselves.
        if (!folder.chosen && !folder.hintHidden)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: KitPanel(
                color: kit.shade(KitHue.books),
                padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
                child: Row(children: [
                  Expanded(
                    child: KitRow(
                      icon: Icons.create_new_folder_outlined,
                      hue: KitHue.books,
                      title: tr('Import books automatically'),
                      subtitle: tr('Choose a folder, like Download/Books'),
                      onTap: () => showBooksFolder(context, ref),
                    ),
                  ),
                  KitIconButton(
                    icon: Icons.close_rounded,
                    semanticLabel: tr('Not now'),
                    size: 36,
                    iconSize: 18,
                    color: kit.inkSoft,
                    onPressed: ref.read(booksFolderProvider.notifier).hideHint,
                  ),
                ]),
              ),
            ),
          ),
        if (books.isEmpty)
          SliverToBoxAdapter(
            child: KitEmpty(
              emoji: '📚',
              title: tr('Your library is empty'),
              message: tr('Import a DRM-free EPUB or a PDF with selectable text.'),
              action: KitButton.secondary(
                label: tr('Add a free classic'),
                onPressed: () => ref.read(libraryProvider.notifier).ensureStarterBook(),
              ),
            ),
          )
        else
          SliverLayoutBuilder(builder: (context, constraints) {
            // Each tile is as tall as its cover plus its text at the phone's
            // text size, so large text never spills out of it.
            const maxWidth = 180.0, spacing = 16.0;
            final columns = (constraints.crossAxisExtent / (maxWidth + spacing)).ceil().clamp(1, 12);
            final tile = (constraints.crossAxisExtent - spacing * (columns - 1)) / columns;
            final scaler = MediaQuery.textScalerOf(context);
            final text = math.max(scaler.scale(14) * 1.2 * 2 + scaler.scale(12.5) * 1.45, 48.0);
            return SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: maxWidth,
              mainAxisSpacing: 20,
              crossAxisSpacing: spacing,
              mainAxisExtent: tile * 1.5 + 8 + 4 + 6 + text + 4,
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
                  // The pink of books while you read it, green once it's finished.
                  KitProgress(
                    value: b.finishedAt != null ? 1 : b.progress,
                    height: 4,
                    color: b.finishedAt != null ? kit.growth : kit.hue(KitHue.books),
                    track: b.finishedAt != null ? kit.growthSoft : kit.shade(KitHue.books),
                  ),
                  const SizedBox(height: 6),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(b.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: kit.strong.copyWith(fontSize: 14, height: 1.2)),
                        Text(
                          b.finishedAt != null ? tr('Finished ✓') : '${(b.progress * 100).round()}% · ${b.author}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: kit.caption.copyWith(fontSize: 12.5, color: b.finishedAt != null ? kit.growth : null),
                        ),
                      ]),
                    ),
                    KitPressable(
                      onTap: () => _bookMenu(b),
                      semanticLabel: tr('More for {title}', {'title': b.title}),
                      excludeSemantics: true,
                      // A 48 dp touch target, the dots in its top corner.
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: Align(
                          alignment: AlignmentDirectional.topEnd,
                          child: Icon(Icons.more_vert_rounded, size: 20, color: kit.inkSoft),
                        ),
                      ),
                    ),
                  ]),
                ]),
              );
            },
          );
          }),
      ],
    );
  }
}
