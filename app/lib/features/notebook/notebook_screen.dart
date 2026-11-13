import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/notebook.dart';
import '../../data/settings.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';
import '../share/share_sheet.dart';

enum _Tab { saved, highlights, words, reflections }

/// Everything the reader kept (UX_DESIGN.md §4): saved cards, highlights,
/// words and reflections, with Markdown export.
class NotebookScreen extends ConsumerStatefulWidget {
  const NotebookScreen({super.key});

  @override
  ConsumerState<NotebookScreen> createState() => _NotebookScreenState();
}

class _NotebookScreenState extends ConsumerState<NotebookScreen> {
  _Tab _tab = _Tab.saved;

  @override
  Widget build(BuildContext context) {
    final n = ref.watch(notebookProvider);
    final counts = {
      _Tab.saved: n.saved.length,
      _Tab.highlights: n.highlights.length,
      _Tab.words: n.words.length,
      _Tab.reflections: n.reflections.length,
    };
    String label(_Tab t) => switch (t) {
          _Tab.saved => 'Saved',
          _Tab.highlights => 'Highlights',
          _Tab.words => 'Words',
          _Tab.reflections => 'Reflections',
        };
    return KitPage(
      back: false,
      backdrop: false,
      dock: true,
      title: 'Notebook',
      actions: [
        KitIconButton(
          icon: Icons.reply_rounded,
          semanticLabel: 'Export as Markdown',
          onPressed: () => SharePlus.instance.share(ShareParams(text: notebookToMarkdown(n), subject: 'My Cloro notebook')),
          child: const ShareArrowIcon(size: 22),
        ),
      ],
      header: SizedBox(
        height: 46,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            for (final t in _Tab.values)
              Padding(
                padding: const EdgeInsets.only(right: 8, bottom: 6),
                child: KitChip(label: '${label(t)} ${counts[t]}', selected: _tab == t, onTap: () => setState(() => _tab = t)),
              ),
          ],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
      children: switch (_tab) {
        _Tab.saved => _saved(context, n.saved),
        _Tab.highlights => _highlights(context, n.highlights),
        _Tab.words => _words(context, n.words),
        _Tab.reflections => _reflections(context, n.reflections),
      },
    );
  }

  List<Widget> _saved(BuildContext context, List<SavedCard> saved) {
    final kit = Kit.of(context);
    if (saved.isEmpty) return const [KitEmpty(emoji: '🔖', title: 'Nothing saved yet', message: 'Tap 🔖 on any card to keep it here.')];
    return [
      for (final s in saved)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: KitPanel(
            onTap: () => context.push('/read/${s.bookId}?sid=${s.startSid}'),
            padding: const EdgeInsets.fromLTRB(16, 16, 6, 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Text(s.text,
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: 'Literata', fontSize: 16, height: 1.45, color: kit.ink)),
              ),
              Row(children: [
                Expanded(child: Text('${s.bookTitle} · ${s.chapterTitle}', style: kit.caption, overflow: TextOverflow.ellipsis)),
                KitIconButton(
                  icon: Icons.reply_rounded,
                  semanticLabel: 'Share',
                  glass: false,
                  onPressed: () => showShareSheet(
                    context,
                    QuoteShare(sentences: [s.text], bookTitle: s.bookTitle, author: s.author, publicDomain: false),
                  ),
                  child: ShareArrowIcon(size: 21, color: kit.inkSoft),
                ),
                KitIconButton(
                  icon: Icons.delete_outline_rounded,
                  semanticLabel: 'Remove',
                  glass: false,
                  color: kit.inkSoft,
                  iconSize: 21,
                  onPressed: () => ref.read(notebookProvider.notifier).removeSaved(s.id),
                ),
              ]),
            ]),
          ),
        ),
    ];
  }

  List<Widget> _highlights(BuildContext context, List<Highlight> highlights) {
    final kit = Kit.of(context);
    if (highlights.isEmpty) {
      return const [KitEmpty(emoji: '✨', title: 'No highlights yet', message: 'Tap a sentence while reading to highlight it.')];
    }
    final colors = ReadingTheme.of(ReadingThemeId.paper).highlights;
    return [
      for (final h in highlights)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Dismissible(
            key: ValueKey(h.id),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 24),
              child: Icon(Icons.delete_outline_rounded, color: kit.danger),
            ),
            onDismissed: (_) => ref.read(notebookProvider.notifier).removeHighlight(h.id),
            child: KitPanel(
              onTap: () => context.push('/read/${h.bookId}?sid=${h.sid}'),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 5,
                  height: 44,
                  decoration: BoxDecoration(color: colors[h.color].withValues(alpha: 1), borderRadius: BorderRadius.circular(3)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(h.text, style: TextStyle(fontFamily: 'Literata', fontSize: 15.5, height: 1.4, color: kit.ink)),
                    const SizedBox(height: 6),
                    Text([h.bookTitle, if (h.note != null && h.note!.isNotEmpty) '📝 ${h.note}'].join('\n'), style: kit.caption),
                  ]),
                ),
              ]),
            ),
          ),
        ),
    ];
  }

  List<Widget> _words(BuildContext context, List<WordEntry> words) {
    final kit = Kit.of(context);
    if (words.isEmpty) {
      return const [KitEmpty(emoji: '🔤', title: 'No words yet', message: 'Long-press any word while reading, then “Add to word list”.')];
    }
    final due = words.where((w) => !w.dueAt.isAfter(DateTime.now())).length;
    return [
      KitButton(
        label: due == 0 ? 'All caught up' : 'Review $due word${due == 1 ? '' : 's'}',
        icon: Icons.style_rounded,
        expand: true,
        kind: due == 0 ? KitButtonKind.secondary : KitButtonKind.primary,
        onPressed: due == 0 ? null : () => context.push('/review'),
      ),
      const SizedBox(height: 12),
      KitGroup(children: [
        for (final w in words)
          KitRow(
            title: w.word,
            subtitle: w.meaning,
            trailing: KitIconButton(
              icon: Icons.close_rounded,
              semanticLabel: 'Remove ${w.word}',
              glass: false,
              color: kit.inkSoft,
              iconSize: 20,
              onPressed: () => ref.read(notebookProvider.notifier).removeWord(w.word),
            ),
          ),
      ]),
    ];
  }

  List<Widget> _reflections(BuildContext context, List<Reflection> reflections) {
    final kit = Kit.of(context);
    if (reflections.isEmpty) {
      return const [KitEmpty(emoji: '💡', title: 'No reflections yet', message: 'At the end of a chapter, write one idea you’ll use.')];
    }
    return [
      for (final r in reflections)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: KitPanel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.text, style: kit.body),
              const SizedBox(height: 8),
              Text('${r.bookTitle} · ${r.chapterTitle}', style: kit.caption),
            ]),
          ),
        ),
    ];
  }
}
