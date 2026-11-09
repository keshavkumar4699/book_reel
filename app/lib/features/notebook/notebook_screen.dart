import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/notebook.dart';
import '../../data/settings.dart';
import '../../ui/theme.dart';
import '../share/share_sheet.dart';

/// Everything the reader kept (UX_DESIGN.md §4): saved cards, highlights,
/// words and reflections, with Markdown export.
class NotebookScreen extends ConsumerWidget {
  const NotebookScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.watch(notebookProvider);
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Notebook'),
          actions: [
            IconButton(
              tooltip: 'Export as Markdown',
              icon: const Icon(Icons.ios_share),
              onPressed: () => SharePlus.instance.share(ShareParams(text: notebookToMarkdown(n), subject: 'My BookReel notebook')),
            ),
          ],
          bottom: TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
            Tab(text: 'Saved (${n.saved.length})'),
            Tab(text: 'Highlights (${n.highlights.length})'),
            Tab(text: 'Words (${n.words.length})'),
            Tab(text: 'Reflections (${n.reflections.length})'),
          ]),
        ),
        body: TabBarView(children: [
          _SavedTab(n.saved),
          _HighlightsTab(n.highlights),
          _WordsTab(n.words),
          _ReflectionsTab(n.reflections),
        ]),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
          ]),
        ),
      );
}

class _SavedTab extends ConsumerWidget {
  const _SavedTab(this.saved);
  final List<SavedCard> saved;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (saved.isEmpty) return const _Empty(Icons.bookmark_border, 'Tap 🔖 on any card to keep it here.');
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: saved.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final s = saved[i];
        return Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => context.push('/read/${s.bookId}?sid=${s.startSid}'),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.text, maxLines: 6, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'Literata', fontSize: 16, height: 1.45)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: Text('${s.bookTitle} · ${s.chapterTitle}', style: Theme.of(context).textTheme.bodySmall, overflow: TextOverflow.ellipsis)),
                  IconButton(
                    tooltip: 'Share',
                    icon: const Icon(Icons.ios_share, size: 20),
                    onPressed: () => showShareSheet(
                      context,
                      QuoteShare(sentences: [s.text], bookTitle: s.bookTitle, author: s.author, publicDomain: false),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: () => ref.read(notebookProvider.notifier).removeSaved(s.id),
                  ),
                ]),
              ]),
            ),
          ),
        );
      },
    );
  }
}

class _HighlightsTab extends ConsumerWidget {
  const _HighlightsTab(this.highlights);
  final List<Highlight> highlights;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (highlights.isEmpty) return const _Empty(Icons.border_color_outlined, 'Double-tap a sentence while reading to highlight it.');
    final colors = ReadingTheme.of(ReadingThemeId.paper).highlights;
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: highlights.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final h = highlights[i];
        return Dismissible(
          key: ValueKey(h.id),
          direction: DismissDirection.endToStart,
          background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 24), child: const Icon(Icons.delete_outline)),
          onDismissed: (_) => ref.read(notebookProvider.notifier).removeHighlight(h.id),
          child: ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            leading: Container(width: 6, height: 40, decoration: BoxDecoration(color: colors[h.color].withValues(alpha: 1), borderRadius: BorderRadius.circular(3))),
            title: Text(h.text, style: const TextStyle(fontFamily: 'Literata', height: 1.4)),
            subtitle: Text([h.bookTitle, if (h.note != null && h.note!.isNotEmpty) '📝 ${h.note}'].join('\n')),
            onTap: () => context.push('/read/${h.bookId}?sid=${h.sid}'),
          ),
        );
      },
    );
  }
}

class _WordsTab extends ConsumerWidget {
  const _WordsTab(this.words);
  final List<WordEntry> words;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (words.isEmpty) return const _Empty(Icons.translate, 'Long-press any word while reading, then “Add to word list”.');
    final due = words.where((w) => !w.dueAt.isAfter(DateTime.now())).length;
    return ListView(padding: const EdgeInsets.all(16), children: [
      FilledButton.tonalIcon(
        onPressed: due == 0 ? null : () => context.push('/review'),
        icon: const Icon(Icons.style_outlined),
        label: Text(due == 0 ? 'All caught up' : 'Review $due word${due == 1 ? '' : 's'}'),
      ),
      const SizedBox(height: 12),
      for (final w in words)
        ListTile(
          title: Text(w.word, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(w.meaning),
          trailing: IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.close),
            onPressed: () => ref.read(notebookProvider.notifier).removeWord(w.word),
          ),
        ),
    ]);
  }
}

class _ReflectionsTab extends StatelessWidget {
  const _ReflectionsTab(this.reflections);
  final List<Reflection> reflections;

  @override
  Widget build(BuildContext context) {
    if (reflections.isEmpty) return const _Empty(Icons.lightbulb_outline, 'At the end of a chapter, write one idea you’ll use.');
    return ListView(padding: const EdgeInsets.all(16), children: [
      for (final r in reflections)
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            title: Text(r.text),
            subtitle: Padding(padding: const EdgeInsets.only(top: 8), child: Text('${r.bookTitle} · ${r.chapterTitle}')),
          ),
        ),
    ]);
  }
}
