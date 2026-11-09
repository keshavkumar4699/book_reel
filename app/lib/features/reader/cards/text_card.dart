import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../core/models/book.dart';
import '../../../core/models/reel_card.dart';
import '../../../core/parsing/block_builder.dart';
import '../../../core/text/lexicon.dart';
import '../../../data/notebook.dart';
import '../../../data/settings.dart';
import '../../../ui/theme.dart';

/// A sentence resolved for rendering.
class CardSentence {
  const CardSentence(this.sentence, this.block, {required this.firstInBlock});
  final Sentence sentence;
  final Block block;
  final bool firstInBlock;
}

/// Renders a text card: the author's words, with key points, user highlights
/// and hard words. Double-tap a sentence to highlight it; long-press a word
/// for its meaning (UX_DESIGN.md §5.2, §5.4, §5.5).
class TextCardView extends StatefulWidget {
  const TextCardView({
    super.key,
    required this.card,
    required this.sentences,
    required this.chapterTitle,
    required this.settings,
    required this.theme,
    required this.lexicon,
    required this.highlightFor,
    required this.onDoubleTapSentence,
    required this.onLongPressWord,
    required this.onOverscroll,
    this.topPadding = 72,
    this.bottomPadding = 96,
    this.hint,
  });

  final SegmentCard card;
  final List<CardSentence> sentences;
  final String chapterTitle;
  final AppSettings settings;
  final ReadingTheme theme;
  final Lexicon lexicon;
  final Highlight? Function(String sid) highlightFor;
  final void Function(Sentence sentence) onDoubleTapSentence;
  final void Function(String word, Sentence sentence) onLongPressWord;

  /// Called when the user keeps dragging past the end (+1) or start (-1) of a
  /// card that is taller than the screen.
  final void Function(int direction) onOverscroll;
  final double topPadding;
  final double bottomPadding;
  final String? hint;

  @override
  State<TextCardView> createState() => _TextCardViewState();
}

class _TextCardViewState extends State<TextCardView> {
  final _textKey = GlobalKey();
  final List<(int start, int end, Sentence sentence)> _ranges = [];
  double _overscroll = 0;
  Offset? _doubleTapPosition;

  Set<String> get _hardWordsLower {
    if (!widget.settings.underlineHardWords) return const {};
    if (widget.card.hardWords.isNotEmpty) {
      return widget.card.hardWords.map((h) => h.word.toLowerCase()).toSet();
    }
    if (widget.lexicon.isEmpty) return const {};
    return {
      for (final s in widget.sentences)
        if (s.block.type != BlockType.heading)
          ...widget.lexicon.hardWords(s.sentence.text, widget.settings.readingLevel).map((w) => w.toLowerCase()),
    };
  }

  TextStyle _baseStyle(BuildContext context) => TextStyle(
        fontFamily: fontFamilyFor(widget.settings.font),
        fontSize: widget.settings.fontSize,
        height: widget.settings.lineHeight,
        letterSpacing: widget.settings.letterSpacing,
        wordSpacing: widget.settings.wordSpacing,
        color: widget.theme.text,
      );

  InlineSpan _buildSpan(BuildContext context) {
    _ranges.clear();
    final base = _baseStyle(context);
    final hard = _hardWordsLower;
    final keySids = widget.settings.keyPointStyle == KeyPointStyle.off ? const <String>{} : widget.card.keySids.toSet();
    final children = <InlineSpan>[];
    var offset = 0;
    int? previousBlock;

    void add(InlineSpan span, int length) {
      children.add(span);
      offset += length;
    }

    for (final cs in widget.sentences) {
      final s = cs.sentence;
      final block = cs.block;
      if (previousBlock != null && previousBlock != block.index) {
        // Paragraph gap: a blank line in a small font gives ~0.6 em spacing.
        add(const TextSpan(text: '\n'), 1);
        add(TextSpan(text: '\n', style: base.copyWith(fontSize: widget.settings.fontSize * 0.55, height: 1)), 1);
      } else if (previousBlock != null) {
        final sep = block.type == BlockType.quote ? '\n' : ' ';
        add(TextSpan(text: sep), sep.length);
      }
      previousBlock = block.index;

      if (isSceneBreakBlock(block)) {
        add(TextSpan(text: '⁂', style: base.copyWith(color: widget.theme.muted)), 1);
        continue;
      }
      var style = base;
      switch (block.type) {
        case BlockType.heading:
          style = style.copyWith(fontWeight: FontWeight.w600, fontSize: widget.settings.fontSize * 1.1);
        case BlockType.quote:
          style = style.copyWith(fontStyle: FontStyle.italic);
        case BlockType.preformatted:
          style = style.copyWith(fontFamily: 'monospace', fontSize: widget.settings.fontSize * 0.85);
        case BlockType.paragraph:
        case BlockType.list:
        case BlockType.dialogue:
          break;
      }
      final highlight = widget.highlightFor(s.id);
      if (highlight != null) {
        style = style.copyWith(backgroundColor: widget.theme.highlights[highlight.color % highlightColorCount]);
      } else if (keySids.contains(s.id)) {
        style = style.copyWith(
          backgroundColor: widget.theme.keyPoint,
          fontWeight: widget.settings.keyPointStyle == KeyPointStyle.bold ? FontWeight.w600 : null,
        );
      }
      final start = offset;
      final text = s.text;
      if (hard.isEmpty) {
        add(TextSpan(text: text, style: style), text.length);
      } else {
        final parts = <InlineSpan>[];
        var last = 0;
        for (final m in RegExp(r"[A-Za-z][A-Za-z'’\-]*").allMatches(text)) {
          if (!hard.contains(m.group(0)!.toLowerCase())) continue;
          if (m.start > last) parts.add(TextSpan(text: text.substring(last, m.start)));
          parts.add(TextSpan(
            text: m.group(0),
            style: TextStyle(
              decoration: TextDecoration.underline,
              decorationStyle: TextDecorationStyle.dotted,
              decorationColor: widget.theme.hardWordUnderline,
              decorationThickness: 2,
            ),
          ));
          last = m.end;
        }
        if (last < text.length) parts.add(TextSpan(text: text.substring(last)));
        add(TextSpan(style: style, children: parts), text.length);
      }
      _ranges.add((start, offset, s));
    }
    return TextSpan(style: base, children: children);
  }

  int? _offsetAt(Offset global) {
    final ro = _textKey.currentContext?.findRenderObject();
    if (ro is! RenderParagraph) return null;
    final local = ro.globalToLocal(global);
    if (local.dy < 0 || local.dy > ro.size.height) return null;
    return ro.getPositionForOffset(local).offset;
  }

  Sentence? _sentenceAt(int offset) {
    for (final r in _ranges) {
      if (offset >= r.$1 && offset <= r.$2) return r.$3;
    }
    return null;
  }

  void _onLongPress(LongPressStartDetails d) {
    final offset = _offsetAt(d.globalPosition);
    if (offset == null) return;
    final sentence = _sentenceAt(offset);
    if (sentence == null) return;
    final range = _ranges.firstWhere((r) => identical(r.$3, sentence));
    final local = (offset - range.$1).clamp(0, sentence.text.length);
    for (final m in RegExp(r"[A-Za-z][A-Za-z'’\-]*[A-Za-z]|[A-Za-z]").allMatches(sentence.text)) {
      if (local >= m.start && local <= m.end) {
        widget.onLongPressWord(m.group(0)!, sentence);
        return;
      }
    }
  }

  void _onDoubleTap() {
    final pos = _doubleTapPosition;
    if (pos == null) return;
    final offset = _offsetAt(pos);
    if (offset == null) return;
    final sentence = _sentenceAt(offset);
    if (sentence != null && sentence.text != sceneBreakMarker) widget.onDoubleTapSentence(sentence);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final titleStyle = TextStyle(
      fontFamily: fontFamilyFor(widget.settings.font),
      fontSize: widget.settings.fontSize * 0.8,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.4,
      color: t.muted,
    );
    final showTitle = widget.settings.showAiTitles && widget.card.title != null;
    final hPad = 24.0;

    return LayoutBuilder(builder: (context, constraints) {
      return NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n is OverscrollNotification) {
            _overscroll += n.overscroll;
            if (_overscroll.abs() > 48) {
              widget.onOverscroll(_overscroll > 0 ? 1 : -1);
              _overscroll = 0;
            }
          } else if (n is ScrollEndNotification) {
            _overscroll = 0;
          }
          return false;
        },
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(hPad, widget.topPadding, hPad, widget.bottomPadding),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (constraints.maxHeight - widget.topPadding - widget.bottomPadding).clamp(0, double.infinity),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showTitle) ...[
                  Semantics(header: true, child: Text(widget.card.title!.toUpperCase(), style: titleStyle)),
                  const SizedBox(height: 16),
                ],
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onDoubleTapDown: (d) => _doubleTapPosition = d.globalPosition,
                  onDoubleTap: _onDoubleTap,
                  onLongPressStart: _onLongPress,
                  child: Text.rich(
                    _buildSpan(context),
                    key: _textKey,
                    textAlign: TextAlign.start,
                    textScaler: MediaQuery.textScalerOf(context),
                  ),
                ),
                if (widget.hint != null) ...[
                  const SizedBox(height: 28),
                  _HintChip(text: widget.hint!, theme: t),
                ],
              ],
            ),
          ),
        ),
      );
    });
  }
}

class _HintChip extends StatelessWidget {
  const _HintChip({required this.text, required this.theme});
  final String text;
  final ReadingTheme theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.keyPoint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.lightbulb_outline, size: 18, color: theme.text),
        const SizedBox(width: 8),
        Flexible(child: Text(text, style: TextStyle(color: theme.text, fontSize: 14))),
      ]),
    );
  }
}
