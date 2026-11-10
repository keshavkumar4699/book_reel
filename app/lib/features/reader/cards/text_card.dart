import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

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

/// A text card styled as a social post over a calm scene: book "author"
/// header, the author's words revealed line by line, and an action row right
/// under the text.
///
/// Gestures: double-tap = like (heart burst) · tap a sentence = highlight ·
/// swipe left = save · swipe right = share · long-press a word = meaning.
class PostCard extends StatefulWidget {
  const PostCard({
    super.key,
    required this.card,
    required this.sentences,
    required this.bookTitle,
    required this.chapterTitle,
    required this.position,
    required this.settings,
    required this.theme,
    required this.accent,
    required this.lexicon,
    required this.active,
    required this.liked,
    required this.saved,
    required this.listening,
    required this.highlightFor,
    required this.onToggleHighlight,
    required this.onLongPressWord,
    required this.onLike,
    required this.onSave,
    required this.onShare,
    required this.onNote,
    required this.onListen,
    required this.onOverscroll,
    this.coverPath,
    this.topPadding = 96,
    this.bottomPadding = 24,
  });

  final SegmentCard card;
  final List<CardSentence> sentences;
  final String bookTitle;
  final String chapterTitle;

  /// e.g. "12 / 48" within the chapter.
  final String position;
  final AppSettings settings;
  final ReadingTheme theme;
  final Color accent;
  final Lexicon lexicon;

  /// True when this card is the one on screen (plays the reveal animation).
  final bool active;
  final bool liked;
  final bool saved;
  final bool listening;
  final Highlight? Function(String sid) highlightFor;
  final void Function(Sentence sentence) onToggleHighlight;
  final void Function(String word, Sentence sentence) onLongPressWord;

  /// Like via the button or double-tap; returns nothing, the parent toggles.
  final VoidCallback onLike;
  final VoidCallback onSave;
  final VoidCallback onShare;
  final VoidCallback onNote;
  final VoidCallback onListen;
  final void Function(int direction) onOverscroll;
  final String? coverPath;
  final double topPadding;
  final double bottomPadding;

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> with TickerProviderStateMixin {
  final _textKey = GlobalKey();
  final List<(int start, int end, Sentence sentence)> _ranges = [];
  late final AnimationController _reveal = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  late final AnimationController _flash = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
  String? _flashSid;
  final List<_Burst> _bursts = [];
  double _dragDx = 0;
  double _overscroll = 0;
  Offset? _doubleTapAt;
  bool _revealed = false;

  @override
  void initState() {
    super.initState();
    _reveal.addListener(() => setState(() {}));
    _flash.addListener(() => setState(() {}));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.active && !_revealed) _startReveal();
  }

  @override
  void didUpdateWidget(PostCard old) {
    super.didUpdateWidget(old);
    if (widget.active && !_revealed) _startReveal();
  }

  /// Text fades in line by line the first time the card is on screen.
  void _startReveal() {
    _revealed = true;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _reveal.value = 1;
    } else {
      _reveal.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _reveal.dispose();
    _flash.dispose();
    for (final b in _bursts) {
      b.controller.dispose();
    }
    super.dispose();
  }

  // ------------------------------------------------------------- text

  Set<String> get _hardWordsLower {
    if (!widget.settings.underlineHardWords) return const {};
    if (widget.card.hardWords.isNotEmpty) return widget.card.hardWords.map((h) => h.word.toLowerCase()).toSet();
    if (widget.lexicon.isEmpty) return const {};
    return {
      for (final s in widget.sentences)
        if (s.block.type != BlockType.heading)
          ...widget.lexicon.hardWords(s.sentence.text, widget.settings.readingLevel).map((w) => w.toLowerCase()),
    };
  }

  /// Fraction (0–1) of sentence [i] that has faded in.
  double _visible(int i, int n) {
    if (_reveal.value >= 1 || n == 0) return 1;
    final per = 1 / n;
    return ((_reveal.value - i * per * 0.75) / (per * 1.25)).clamp(0, 1).toDouble();
  }

  InlineSpan _buildSpan(TextStyle base) {
    _ranges.clear();
    final t = widget.theme;
    final hard = _hardWordsLower;
    final keySids = widget.settings.keyPointStyle == KeyPointStyle.off ? const <String>{} : widget.card.keySids.toSet();
    final children = <InlineSpan>[];
    var offset = 0;
    int? previousBlock;
    final n = widget.sentences.length;

    void add(InlineSpan span, int length) {
      children.add(span);
      offset += length;
    }

    for (var i = 0; i < n; i++) {
      final cs = widget.sentences[i];
      final s = cs.sentence;
      final block = cs.block;
      if (previousBlock != null && previousBlock != block.index) {
        add(const TextSpan(text: '\n'), 1);
        add(TextSpan(text: '\n', style: base.copyWith(fontSize: base.fontSize! * 0.5, height: 1)), 1);
      } else if (previousBlock != null) {
        final sep = block.type == BlockType.quote ? '\n' : ' ';
        add(TextSpan(text: sep), sep.length);
      }
      previousBlock = block.index;
      final alpha = _visible(i, n);
      var style = base.copyWith(color: t.text.withValues(alpha: t.text.a * alpha));
      if (isSceneBreakBlock(block)) {
        add(TextSpan(text: '⁂', style: style.copyWith(color: t.muted)), 1);
        continue;
      }
      switch (block.type) {
        case BlockType.heading:
          style = style.copyWith(fontWeight: FontWeight.w700);
        case BlockType.quote:
          style = style.copyWith(fontStyle: FontStyle.italic);
        case BlockType.preformatted:
          style = style.copyWith(fontFamily: 'monospace', fontSize: base.fontSize! * 0.85);
        case BlockType.paragraph:
        case BlockType.list:
        case BlockType.dialogue:
          break;
      }
      final highlight = widget.highlightFor(s.id);
      if (highlight != null) {
        var color = t.highlights[highlight.color % highlightColorCount];
        if (_flashSid == s.id) color = color.withValues(alpha: color.a * Curves.easeOut.transform(_flash.value));
        style = style.copyWith(backgroundColor: color);
      } else if (keySids.contains(s.id)) {
        style = style.copyWith(
          backgroundColor: t.keyPoint,
          fontWeight: widget.settings.keyPointStyle == KeyPointStyle.bold ? FontWeight.w700 : FontWeight.w600,
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
              decorationColor: t.hardWordUnderline.withValues(alpha: alpha),
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
    if (local.dy < 0 || local.dy > ro.size.height || local.dx < 0 || local.dx > ro.size.width) return null;
    return ro.getPositionForOffset(local).offset;
  }

  Sentence? _sentenceAt(int offset) {
    for (final r in _ranges) {
      if (offset >= r.$1 && offset <= r.$2) return r.$3;
    }
    return null;
  }

  // ------------------------------------------------------------- gestures

  void _onTapUp(TapUpDetails d) {
    final offset = _offsetAt(d.globalPosition);
    if (offset == null) return;
    final sentence = _sentenceAt(offset);
    if (sentence == null || sentence.text == sceneBreakMarker) return;
    HapticFeedback.selectionClick();
    final wasHighlighted = widget.highlightFor(sentence.id) != null;
    widget.onToggleHighlight(sentence);
    if (!wasHighlighted) {
      _flashSid = sentence.id;
      _flash.forward(from: 0);
    }
  }

  void _onDoubleTap() {
    HapticFeedback.mediumImpact();
    if (!widget.liked) widget.onLike();
    final at = _doubleTapAt;
    if (at == null) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final burst = _Burst(box.globalToLocal(at), AnimationController(vsync: this, duration: const Duration(milliseconds: 750)));
    burst.controller
      ..addListener(() => setState(() {}))
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _bursts.remove(burst));
          burst.controller.dispose();
        }
      })
      ..forward();
    setState(() => _bursts.add(burst));
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
        HapticFeedback.selectionClick();
        widget.onLongPressWord(m.group(0)!, sentence);
        return;
      }
    }
  }

  static const _swipeTrigger = 72.0;

  void _onDragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    final dx = _dragDx;
    setState(() => _dragDx = 0);
    if (dx <= -_swipeTrigger || v < -900) {
      HapticFeedback.mediumImpact();
      widget.onSave();
    } else if (dx >= _swipeTrigger || v > 900) {
      HapticFeedback.lightImpact();
      widget.onShare();
    }
  }

  // ------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final s = widget.settings;
    final base = TextStyle(
      fontFamily: fontFamilyFor(s.font),
      fontSize: s.fontSize,
      height: s.lineHeight < 1.4 ? 1.4 : s.lineHeight,
      letterSpacing: s.letterSpacing,
      wordSpacing: s.wordSpacing,
      fontWeight: FontWeight.w500,
      color: t.text,
    );
    final onScene = t.glass.a > 0;
    final glass = onScene ? t.glass : t.background;
    final hasTitle = s.showAiTitles && (widget.card.title?.isNotEmpty ?? false);

    final post = Container(
      decoration: BoxDecoration(
        color: glass,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: onScene ? const Color(0x24FFFFFF) : t.muted.withValues(alpha: 0.18)),
        boxShadow: onScene ? const [BoxShadow(color: Color(0x40000000), blurRadius: 30, offset: Offset(0, 12))] : null,
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        _PostHeader(
          title: widget.bookTitle,
          subtitle: widget.chapterTitle,
          position: widget.position,
          coverPath: widget.coverPath,
          theme: t,
          accent: widget.accent,
        ),
        const SizedBox(height: 16),
        if (hasTitle) ...[
          Text(widget.card.title!, style: TextStyle(color: widget.accent, fontWeight: FontWeight.w700, fontSize: 14, letterSpacing: 0.3)),
          const SizedBox(height: 8),
        ],
        Flexible(
          child: NotificationListener<ScrollNotification>(
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
              child: Text.rich(_buildSpan(base), key: _textKey, textScaler: MediaQuery.textScalerOf(context)),
            ),
          ),
        ),
        const SizedBox(height: 10),
        _ActionBar(
          color: t.text,
          accent: widget.accent,
          liked: widget.liked,
          saved: widget.saved,
          listening: widget.listening,
          onLike: () {
            HapticFeedback.lightImpact();
            widget.onLike();
          },
          onSave: () {
            HapticFeedback.lightImpact();
            widget.onSave();
          },
          onNote: widget.onNote,
          onShare: widget.onShare,
          onListen: widget.onListen,
        ),
      ]),
    );

    final reveal = (_dragDx.abs() / _swipeTrigger).clamp(0.0, 1.0);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: _onTapUp,
      onDoubleTapDown: (d) => _doubleTapAt = d.globalPosition,
      onDoubleTap: _onDoubleTap,
      onLongPressStart: _onLongPress,
      onHorizontalDragUpdate: (d) => setState(() => _dragDx = (_dragDx + d.delta.dx).clamp(-120.0, 120.0)),
      onHorizontalDragEnd: _onDragEnd,
      child: Stack(children: [
        // Swipe hints revealed behind the post.
        if (_dragDx != 0)
          Positioned.fill(
            child: Align(
              alignment: _dragDx < 0 ? Alignment.centerRight : Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Opacity(
                  opacity: reveal,
                  child: _SwipeHint(
                    icon: _dragDx < 0 ? (widget.saved ? Icons.bookmark_remove : Icons.bookmark_add) : Icons.ios_share,
                    label: _dragDx < 0 ? (widget.saved ? 'Unsave' : 'Save') : 'Share',
                    color: widget.accent,
                    armed: reveal >= 1,
                  ),
                ),
              ),
            ),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(14, widget.topPadding, 14, widget.bottomPadding),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Transform.translate(
                offset: Offset(_dragDx * 0.8, 0),
                child: Transform.rotate(angle: _dragDx / 3000, child: post),
              ),
            ),
          ),
        ),
        for (final b in _bursts) _HeartBurstView(burst: b, color: const Color(0xFFFF5A79)),
      ]),
    );
  }
}

class _PostHeader extends StatelessWidget {
  const _PostHeader({
    required this.title,
    required this.subtitle,
    required this.position,
    required this.theme,
    required this.accent,
    this.coverPath,
  });

  final String title;
  final String subtitle;
  final String position;
  final ReadingTheme theme;
  final Color accent;
  final String? coverPath;

  @override
  Widget build(BuildContext context) {
    final cover = coverPath != null && File(coverPath!).existsSync() ? FileImage(File(coverPath!)) : null;
    final initials = title.trim().isEmpty ? '📖' : title.trim()[0].toUpperCase();
    return Row(children: [
      Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [accent, accent.withValues(alpha: 0.4)])),
        child: CircleAvatar(
          radius: 17,
          backgroundColor: const Color(0xFF2F3A35),
          backgroundImage: cover,
          child: cover == null
              ? Text(initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontFamily: 'Literata'))
              : null,
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.text, fontWeight: FontWeight.w700, fontSize: 14)),
          Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.muted, fontSize: 12)),
        ]),
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: theme.text.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(20)),
        child: Text(position, style: TextStyle(color: theme.muted, fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    ]);
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.color,
    required this.accent,
    required this.liked,
    required this.saved,
    required this.listening,
    required this.onLike,
    required this.onSave,
    required this.onNote,
    required this.onShare,
    required this.onListen,
  });

  final Color color;
  final Color accent;
  final bool liked;
  final bool saved;
  final bool listening;
  final VoidCallback onLike;
  final VoidCallback onSave;
  final VoidCallback onNote;
  final VoidCallback onShare;
  final VoidCallback onListen;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      _ActionButton(
        icon: liked ? Icons.favorite : Icons.favorite_border,
        label: liked ? 'Liked' : 'Like',
        tooltip: liked ? 'Unlike' : 'Like',
        color: liked ? const Color(0xFFFF5A79) : color,
        active: liked,
        onTap: onLike,
      ),
      _ActionButton(
        icon: saved ? Icons.bookmark : Icons.bookmark_border,
        label: saved ? 'Saved' : 'Save',
        tooltip: saved ? 'Saved' : 'Save',
        color: saved ? accent : color,
        active: saved,
        onTap: onSave,
      ),
      _ActionButton(icon: Icons.edit_note, label: 'Note', tooltip: 'Highlight & note', color: color, onTap: onNote),
      _ActionButton(icon: Icons.ios_share, label: 'Share', tooltip: 'Share', color: color, onTap: onShare),
      _ActionButton(
        icon: listening ? Icons.stop_circle_outlined : Icons.headphones_outlined,
        label: listening ? 'Stop' : 'Listen',
        tooltip: listening ? 'Stop reading aloud' : 'Read aloud',
        color: listening ? accent : color,
        active: listening,
        onTap: onListen,
      ),
    ]);
  }
}

/// Icon + label with a springy pop when it becomes active.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.color,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 32,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 52, minHeight: 52),
          child: Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
            TweenAnimationBuilder<double>(
              key: ValueKey(active),
              tween: Tween(begin: active ? 0.6 : 1, end: 1),
              duration: const Duration(milliseconds: 420),
              curve: Curves.elasticOut,
              builder: (context, v, child) => Transform.scale(scale: v, child: child),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: color.withValues(alpha: 0.85), fontSize: 11, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}

class _SwipeHint extends StatelessWidget {
  const _SwipeHint({required this.icon, required this.label, required this.color, required this.armed});
  final IconData icon;
  final String label;
  final Color color;
  final bool armed;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: armed ? 1.15 : 1,
      duration: const Duration(milliseconds: 150),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        CircleAvatar(radius: 26, backgroundColor: armed ? color : const Color(0x66000000), child: Icon(icon, color: Colors.white)),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, shadows: [Shadow(blurRadius: 6)])),
      ]),
    );
  }
}

class _Burst {
  _Burst(this.at, this.controller);
  final Offset at;
  final AnimationController controller;
}

/// Instagram-style heart that pops where you double-tapped, with sparks.
class _HeartBurstView extends StatelessWidget {
  const _HeartBurstView({required this.burst, required this.color});
  final _Burst burst;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final v = burst.controller.value;
    final scale = v < 0.35 ? Curves.easeOutBack.transform(v / 0.35) * 1.2 : 1.2 - (v - 0.35) * 0.3;
    final opacity = v < 0.7 ? 1.0 : (1 - (v - 0.7) / 0.3).clamp(0.0, 1.0);
    return Positioned(
      left: burst.at.dx - 60,
      top: burst.at.dy - 60 - v * 40,
      width: 120,
      height: 120,
      child: IgnorePointer(
        child: Opacity(
          opacity: opacity,
          child: CustomPaint(
            painter: _SparkPainter(v, color),
            child: Center(
              child: Transform.scale(
                scale: scale,
                child: Icon(Icons.favorite, size: 84, color: color, shadows: const [Shadow(color: Color(0x66000000), blurRadius: 16)]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.v, this.color);
  final double v;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (v < 0.15) return;
    final c = size.center(Offset.zero);
    final p = Paint()..color = color.withValues(alpha: (1 - v).clamp(0, 1));
    for (var i = 0; i < 8; i++) {
      final angle = i * 3.14159 / 4;
      final r = 30 + v * 34;
      canvas.drawCircle(c + Offset.fromDirection(angle, r), 4 * (1 - v) + 1, p);
    }
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.v != v;
}
