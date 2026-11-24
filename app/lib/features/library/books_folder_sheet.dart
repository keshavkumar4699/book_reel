import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/book.dart';
import '../../l10n/l10n.dart';
import '../../services/books_folder.dart';
import '../../ui/haptics.dart';
import '../../ui/kit.dart';

/// The books folder (Library and Settings): choose one, look for new books
/// in it now, choose another, or stop importing from it.
Future<void> showBooksFolder(BuildContext context, WidgetRef ref) async {
  final folder = ref.read(booksFolderProvider);
  final notifier = ref.read(booksFolderProvider.notifier);
  if (!folder.chosen) {
    final go = await showKitConfirm(
      context,
      title: tr('Import books automatically'),
      message: tr('Pick a folder on your phone, like Download/Books. Every EPUB or PDF you put in it shows up in your Library by itself.'),
      confirm: tr('Choose folder'),
    );
    if (!go || !context.mounted) return;
    final added = await notifier.choose();
    if (context.mounted) reportBooksFolder(context, ref.read(booksFolderProvider), added);
    return;
  }
  final action = await showKitActions<String>(
    context,
    title: folder.name == null || folder.name!.isEmpty ? tr('Books folder') : folder.name,
    subtitle: folder.unavailable
        ? tr('Cloro can’t read this folder any more (moved, deleted, or its access taken back). Choose it again.')
        : tr('Every EPUB or PDF you put in this folder shows up in your Library by itself.'),
    actions: [
      if (!folder.unavailable) KitAction('scan', tr('Look for new books now'), icon: Icons.refresh_rounded),
      KitAction('choose', folder.unavailable ? tr('Choose it again') : tr('Choose another folder'), icon: Icons.folder_open_rounded),
      KitAction('stop', tr('Stop importing from this folder'), icon: Icons.folder_off_outlined, destructive: true),
    ],
  );
  if (!context.mounted) return;
  switch (action) {
    case 'scan':
      final added = await notifier.scan(force: true);
      if (context.mounted) reportBooksFolder(context, ref.read(booksFolderProvider), added);
    case 'choose':
      final added = await notifier.choose();
      if (context.mounted) reportBooksFolder(context, ref.read(booksFolderProvider), added);
    case 'stop':
      Haptics.press();
      await notifier.forget();
      if (context.mounted) showKitToast(context, tr('Books in your Library stay; new ones in the folder won’t be added'), icon: Icons.folder_off_outlined);
  }
}

/// What a look in the folder found. [added] null: no folder was chosen.
void reportBooksFolder(BuildContext context, BooksFolderState folder, List<BookMeta>? added) {
  if (added == null || !folder.chosen) return;
  final name = folder.name == null || folder.name!.isEmpty ? tr('your books folder') : folder.name!;
  if (folder.unavailable) {
    showKitToast(context, tr('Can’t read {folder}. Choose it again.', {'folder': name}), icon: Icons.folder_off_outlined);
  } else if (added.isEmpty) {
    showKitToast(context, tr('No new books in {folder}', {'folder': name}), icon: Icons.folder_outlined);
  } else {
    Haptics.success();
    showKitToast(context, trn(added.length, 'Added {n} book from {folder}', 'Added {n} books from {folder}', {'folder': name}), emoji: '📚');
  }
}
