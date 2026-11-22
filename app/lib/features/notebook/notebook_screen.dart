import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/notebook.dart';
import '../../data/settings.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';
import '../share/share_sheet.dart';
import '../../l10n/l10n.dart';

enum _Tab { all, saved, highlights, words, reflections }

/// Each kind of note's colour: a very light shade of it behind the note in
/// All (so kinds tell apart at a glance), and a dot by its name.
Color _hue(_Tab t) => switch (t) {
      _Tab.saved => const Color(0xFF1A73E8),
      _Tab.highlights => const Color(0xFFE8A200),
      _Tab.words => const Color(0xFF188038),
      _Tab.reflections => const Color(0xFF9334E6),
      _Tab.all => const Color(0xFF80868B),
    };

/// The very light shade of [t]'s colour on the page.
Color notebookShade(Kit kit, Color hue) => Color.alphaBlend(hue.withValues(alpha: kit.dark ? 0.13 : 0.065), kit.base);

/// Everything the reader kept (UX_DESIGN.md §4): saved cards, highlights,
/// words and reflections, with Markdown export. All shows them together,
/// newest first, each kind on its own very light shade.
class NotebookScreen extends ConsumerStatefulWidget {
  const NotebookScreen({super.key});

  @override
  ConsumerState<NotebookScreen> createState() => _NotebookScreenState();
}

class _NotebookScreenState extends ConsumerState<NotebookScreen> {
  _Tab _tab = _Tab.all;

  @override
  Widget build(BuildContext context) {
    final n = ref.watch(notebookProvider);
    final counts = {
      _Tab.all: n.saved.length + n.highlights.length + n.words.length + n.reflections.length,
      _Tab.saved: n.saved.length,
      _Tab.highlights: n.highlights.length,
      _Tab.words: n.words.length,
      _Tab.reflections: n.reflections.length,
    };
    String label(_Tab t) => switch (t) {
          _Tab.all => tr('All'),
          _Tab.saved => tr('Saved'),
          _Tab.highlights => tr('Highlights'),
          _Tab.words => tr('Words'),
          _Tab.reflections => tr('Reflections'),
        };
    return KitPage(
      back: false,
      backdrop: false,
      dock: true,
      title: tr('Notebook'),
      actions: [
        KitIconButton(
          icon: Icons.reply_rounded,
          semanticLabel: tr('Export as Markdown'),
          onPressed: () => SharePlus.instance.share(ShareParams(text: notebookToMarkdown(n), subject: tr('My Cloro notebook'))),
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
        _Tab.all => _all(context, n),
        _Tab.saved => _saved(context, n.saved),
        _Tab.highlights => _highlights(context, n.highlights),
        _Tab.words => _words(context, n.words),
        _Tab.reflections => _reflections(context, n.reflections),
      },
    );
  }

  /// Everything, newest first: each note on the very light shade of its
  /// kind, with the kind named in its colour.
  List<Widget> _all(BuildContext context, NotebookState n) {
    final kit = Kit.of(context);
    final colors = ReadingTheme.of(ReadingThemeId.paper).highlights;
    final items = <({DateTime at, _Tab kind, String text, String? quote, String source, String? link, Color? mark})>[
      for (final s in n.saved)
        (at: s.createdAt, kind: _Tab.saved, text: s.text, quote: null, source: '${s.bookTitle} · ${s.chapterTitle}', link: '/read/${s.bookId}?sid=${s.startSid}', mark: null),
      for (final h in n.highlights)
        (
          at: h.createdAt,
          kind: _Tab.highlights,
          text: h.text,
          quote: h.note != null && h.note!.isNotEmpty ? '📝 ${h.note}' : null,
          source: h.bookTitle,
          link: '/read/${h.bookId}?sid=${h.sid}',
          mark: colors[h.color % colors.length].withValues(alpha: 1),
        ),
      for (final w in n.words)
        (at: w.addedAt, kind: _Tab.words, text: w.word, quote: w.meaning, source: w.bookTitle, link: null, mark: null),
      for (final r in n.reflections)
        (at: r.createdAt, kind: _Tab.reflections, text: r.text, quote: r.quote == null ? null : '“${r.quote}”', source: '${r.bookTitle} · ${r.chapterTitle}', link: null, mark: null),
    ]..sort((a, b) => b.at.compareTo(a.at));
    if (items.isEmpty) {
      return [
        KitEmpty(emoji: '📓', title: tr('Your notebook is empty'), message: tr('Save a card, highlight a line or look up a word while reading: it all lands here.')),
      ];
    }
    String kind(_Tab t) => switch (t) {
          _Tab.saved => tr('Saved'),
          _Tab.highlights => tr('Highlight'),
          _Tab.words => tr('Word'),
          _Tab.reflections => tr('Reflection'),
          _Tab.all => '',
        };
    return [
      for (final i in items)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: KitPanel(
            color: notebookShade(kit, _hue(i.kind)),
            radius: 16,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            onTap: i.link == null ? null : () => context.go(i.link!),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 7, height: 7, decoration: BoxDecoration(color: _hue(i.kind), shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(kind(i.kind).toUpperCase(), style: kit.label.copyWith(fontSize: 11, letterSpacing: 0.8)),
              ]),
              const SizedBox(height: 8),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (i.mark != null) ...[
                  Container(width: 4, height: 40, decoration: BoxDecoration(color: i.mark, borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    i.text,
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                    style: i.kind == _Tab.words
                        ? kit.heading.copyWith(fontSize: 17)
                        : i.kind == _Tab.reflections
                            ? kit.body
                            : TextStyle(fontFamily: 'Literata', fontSize: 15.5, height: 1.42, color: kit.ink),
                  ),
                ),
              ]),
              if (i.quote != null && i.quote!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(i.quote!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: kit.caption.copyWith(fontStyle: i.kind == _Tab.reflections ? FontStyle.italic : null)),
              ],
              const SizedBox(height: 6),
              Text(i.source, maxLines: 1, overflow: TextOverflow.ellipsis, style: kit.caption.copyWith(fontSize: 12.5)),
            ]),
          ),
        ),
    ];
  }

  List<Widget> _saved(BuildContext context, List<SavedCard> saved) {
    final kit = Kit.of(context);
    if (saved.isEmpty) return [KitEmpty(emoji: '🔖', title: tr('Nothing saved yet'), message: tr('Tap 🔖 on any card to keep it here.'))];
    return [
      for (final s in saved)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: KitPanel(
            onTap: () => context.go('/read/${s.bookId}?sid=${s.startSid}'),
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
                  semanticLabel: tr('Share'),
                  glass: false,
                  onPressed: () => showShareSheet(
                    context,
                    QuoteShare(sentences: [s.text], bookTitle: s.bookTitle, author: s.author, publicDomain: false),
                  ),
                  child: ShareArrowIcon(size: 21, color: kit.inkSoft),
                ),
                KitIconButton(
                  icon: Icons.delete_outline_rounded,
                  semanticLabel: tr('Remove'),
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
      return [KitEmpty(emoji: '✨', title: tr('No highlights yet'), message: tr('Tap a sentence while reading to highlight it.'))];
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
              onTap: () => context.go('/read/${h.bookId}?sid=${h.sid}'),
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
      return [KitEmpty(emoji: '🔤', title: tr('No words yet'), message: tr('Long-press any word while reading, then “Add to word list”.'))];
    }
    final due = words.where((w) => !w.dueAt.isAfter(DateTime.now())).length;
    return [
      KitButton(
        label: due == 0 ? tr('All caught up') : trn(due, 'Review {n} word', 'Review {n} words'),
        icon: Icons.style_rounded,
        expand: true,
        kind: due == 0 ? KitButtonKind.secondary : KitButtonKind.primary,
        onPressed: due == 0 ? null : () => context.push('/review'),
      ),
      const SizedBox(height: 12),
      KitGroup(divided: true, children: [
        for (final w in words)
          KitRow(
            title: w.word,
            subtitle: w.meaning,
            trailing: KitIconButton(
              icon: Icons.close_rounded,
              semanticLabel: tr('Remove {word}', {'word': w.word}),
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
      return [KitEmpty(emoji: '💡', title: tr('No reflections yet'), message: tr('At the end of a chapter, write one idea you’ll use.'))];
    }
    return [
      for (final r in reflections)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: KitPanel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.text, style: kit.body),
              if (r.quote != null) ...[
                const SizedBox(height: 6),
                Text('“${r.quote}”', maxLines: 3, overflow: TextOverflow.ellipsis, style: kit.caption.copyWith(fontStyle: FontStyle.italic)),
              ],
              const SizedBox(height: 8),
              Text('${r.bookTitle} · ${r.chapterTitle}', style: kit.caption),
            ]),
          ),
        ),
    ];
  }
}
