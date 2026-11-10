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
import '../../../ui/typography.dart';
import '../../../core/text/lyric_layout.dart';

/// A sentence resolved for rendering.
class CardSentence {
  const CardSentence(this.sentence, this.block, {required this.firstInBlock});
  final Sentence sentence;
  final Block block;
  final bool firstInBlock;
}

/// A text reel, full screen: the author's words in the book's own body font,
/// one comfortable size for every line, a phrase per line, with generous
/// space around them. A spotlight reel shows one hero line on its own, large,
/// in the book's display font — big and small type never share a screen.
///
/// Gestures: double-tap = like (heart burst) · tap a line = highlight its
/// sentence · swipe left = save · swipe right = share · long-press a word =
/// meaning. Actions also sit in a right-hand rail, Reels style.
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
    required this.type,
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
    this.spotlight = false,
    this.lines,
    this.coverPath,
  });

  final SegmentCard card;

  /// The sentences this reel is laid out from (all of the card, or one part).
  final List<CardSentence> sentences;

  /// When the text continues over several reels: the display lines on this one.
  final ({int from, int to})? lines;
  final String bookTitle;
  final String chapterTitle;

  /// e.g. "12 / 48" within the chapter.
  final String position;
  final AppSettings settings;
  final ReadingTheme theme;

  /// The book's fonts (its typographic voice, or the reader's chosen font).
  final BookType type;
  final Lexicon lexicon;

  /// True when this card is the one on screen (plays the entrance animation).
  final bool active;
  final bool liked;
  final bool saved;
  final bool listening;
  final Highlight? Function(String sid) highlightFor;
  final void Function(Sentence sentence) onToggleHighlight;
  final void Function(String word, Sentence sentence) onLongPressWord;
  final VoidCallback onLike;
  final VoidCallback onSave;
  final VoidCallback onShare;
  final VoidCallback onNote;
  final VoidCallback onListen;
  final void Function(int direction) onOverscroll;

  /// Show the (single) sentence as a spotlight line.
  final bool spotlight;
  final String? coverPath;

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> with TickerProviderStateMixin {
  final _textKey = GlobalKey<_ReelTextState>();
  late final AnimationController _reveal =
      AnimationController(vsync: this, duration: Duration(milliseconds: widget.spotlight ? 900 : 1100));
  late final AnimationController _flash = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
  String? _flashSid;
  final List<_Burst> _bursts = [];
  double _dragDx = 0;
  Offset? _doubleTapAt;
  bool _revealed = false;
  late List<LyricPiece> _pieces;
  late LyricAlign _align;
  ({int start, int end})? _focus;

  @override
  void initState() {
    super.initState();
    _reveal.addListener(() => setState(() {}));
    _flash.addListener(() => setState(() {}));
    _buildPieces();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.active && !_revealed) _startReveal();
  }

  @override
  void didUpdateWidget(PostCard old) {
    super.didUpdateWidget(old);
    if (!identical(old.card, widget.card) ||
        old.sentences.length != widget.sentences.length ||
        old.spotlight != widget.spotlight ||
        old.lines != widget.lines) {
      _buildPieces();
    }
    if (widget.active && !_revealed) _startReveal();
  }

  void _buildPieces() {
    if (widget.spotlight && widget.sentences.isNotEmpty) {
      final s = widget.sentences.first;
      final text = s.sentence.text;
      _pieces = [LyricPiece(text: text, sid: s.sentence.id, level: 3, start: 0, end: text.length, blockType: s.block.type)];
      _focus = spotlightFocus(text, widget.card.emphasis, s.sentence.id);
      _align = LyricAlign.centered;
      return;
    }
    _focus = null;
    final all = piecesForCard(widget.card, [
      for (final s in widget.sentences) (sid: s.sentence.id, text: s.sentence.text, block: s.block.index, type: s.block.type),
    ]);
    // One alignment for every reel of the same text.
    _align = lyricAlignFor(widget.card.layout, all);
    final r = widget.lines;
    _pieces = limitEmphasis(r == null ? all : all.sublist(r.from.clamp(0, all.length), r.to.clamp(0, all.length)));
  }

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

  Sentence? _sentence(String sid) => widget.sentences.where((s) => s.sentence.id == sid).firstOrNull?.sentence;

  // ------------------------------------------------------------- gestures

  void _onTapUp(TapUpDetails d) {
    final hit = _textKey.currentState?.hitTest(d.globalPosition);
    if (hit == null) return;
    final sentence = _sentence(hit.piece.sid);
    if (sentence == null || sentence.text == sceneBreakMarker) return;
    HapticFeedback.selectionClick();
    final was = widget.highlightFor(sentence.id) != null;
    widget.onToggleHighlight(sentence);
    if (!was) {
      _flashSid = sentence.id;
      _flash.forward(from: 0);
    }
  }

  void _onDoubleTap() {
    HapticFeedback.mediumImpact();
    if (!widget.liked) widget.onLike();
    final at = _doubleTapAt;
    final box = context.findRenderObject() as RenderBox?;
    if (at == null || box == null) return;
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
    final hit = _textKey.currentState?.hitTest(d.globalPosition);
    if (hit == null) return;
    final sentence = _sentence(hit.piece.sid);
    if (sentence == null) return;
    final local = (hit.piece.start + hit.offset).clamp(0, sentence.text.length);
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

  Set<String> get _hardWordsLower {
    if (!widget.settings.underlineHardWords || widget.spotlight) return const {};
    if (widget.card.hardWords.isNotEmpty) return widget.card.hardWords.map((h) => h.word.toLowerCase()).toSet();
    if (widget.lexicon.isEmpty) return const {};
    return {
      for (final s in widget.sentences)
        if (s.block.type != BlockType.heading)
          ...widget.lexicon.hardWords(s.sentence.text, widget.settings.readingLevel).map((w) => w.toLowerCase()),
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final padding = MediaQuery.paddingOf(context);
    final screen = MediaQuery.sizeOf(context);
    final leftHanded = widget.settings.leftHanded;
    const railWidth = 72.0;
    final reveal = (_dragDx.abs() / _swipeTrigger).clamp(0.0, 1.0);
    // The text never fills the screen: the scene shows above and below it.
    final zone = reelTextInsets(screen: screen, topInset: padding.top, bottomInset: padding.bottom);

    final text = ReelText(
      key: _textKey,
      pieces: _pieces,
      align: _align,
      spotlight: widget.spotlight,
      focus: _focus,
      progress: _reveal.value,
      type: widget.type,
      theme: t,
      hardWords: _hardWordsLower,
      highlightColor: (sid) {
        final h = widget.highlightFor(sid);
        if (h == null) return null;
        var color = t.highlights[h.color % highlightColorCount];
        if (_flashSid == sid) color = color.withValues(alpha: color.a * Curves.easeOut.transform(_flash.value));
        return color;
      },
      onOverscroll: widget.onOverscroll,
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: _onTapUp,
      onDoubleTapDown: (d) => _doubleTapAt = d.globalPosition,
      onDoubleTap: _onDoubleTap,
      onLongPressStart: _onLongPress,
      onHorizontalDragUpdate: (d) => setState(() => _dragDx = (_dragDx + d.delta.dx).clamp(-120.0, 120.0)),
      onHorizontalDragEnd: _onDragEnd,
      child: Stack(children: [
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
                    color: t.accent,
                    armed: reveal >= 1,
                  ),
                ),
              ),
            ),
          ),
        // The text sits in a calm column well inside the screen.
        Positioned(
          top: zone.top,
          bottom: zone.bottom,
          left: leftHanded ? reelRailMargin : reelSideMargin,
          right: leftHanded ? reelSideMargin : reelRailMargin,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: reelMaxTextWidth),
              child: Transform.translate(offset: Offset(_dragDx * 0.6, 0), child: text),
            ),
          ),
        ),
        // Book row (bottom-left, like the account line on a reel).
        Positioned(
          left: leftHanded ? railWidth : 16,
          right: leftHanded ? 16 : railWidth,
          bottom: padding.bottom + 22,
          child: _BookRow(
            title: widget.bookTitle,
            subtitle: '${widget.chapterTitle} · ${widget.position}',
            coverPath: widget.coverPath,
            ink: t.text,
            accent: t.accent,
            shadows: t.textShadows,
          ),
        ),
        // Action rail (bottom-right; mirrored for left-handed readers).
        Positioned(
          right: leftHanded ? null : 4,
          left: leftHanded ? 4 : null,
          bottom: padding.bottom + 16,
          width: railWidth - 8,
          child: _ActionRail(
            ink: t.text,
            accent: t.accent,
            shadows: t.textShadows,
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
        ),
        for (final b in _bursts) _HeartBurstView(burst: b, color: const Color(0xFFFF5A79)),
      ]),
    );
  }
}

class LyricHit {
  const LyricHit(this.piece, this.offset);
  final LyricPiece piece;

  /// Character offset within the piece's text.
  final int offset;
}

/// Lays out a reel's lines. Regular reels use the reader's size (shrinking
/// only when the text would not fit, never growing to fill the screen);
/// spotlight reels size one line in the display face within a calm range.
class ReelText extends StatefulWidget {
  const ReelText({
    super.key,
    required this.pieces,
    required this.align,
    required this.progress,
    required this.type,
    required this.theme,
    required this.hardWords,
    required this.highlightColor,
    required this.onOverscroll,
    this.spotlight = false,
    this.focus,
  });

  final List<LyricPiece> pieces;
  final LyricAlign align;

  /// Entrance animation progress, 0–1.
  final double progress;
  final BookType type;
  final ReadingTheme theme;
  final Set<String> hardWords;
  final Color? Function(String sid) highlightColor;
  final void Function(int direction) onOverscroll;
  final bool spotlight;

  /// Part of the spotlight line drawn in the spotlight colour.
  final ({int start, int end})? focus;

  @override
  State<ReelText> createState() => _ReelTextState();
}

class _ReelTextState extends State<ReelText> {
  final List<GlobalKey> _keys = [];
  double _overscroll = 0;
  Object? _fitKey;

  /// Regular reels: scale of the body size. Spotlights: the font size.
  double _fit = 1;
  bool _overflows = false;

  /// Finds the piece and character under [global], for tap and long-press.
  LyricHit? hitTest(Offset global) {
    for (var i = 0; i < _keys.length && i < widget.pieces.length; i++) {
      final ro = _keys[i].currentContext?.findRenderObject();
      if (ro is! RenderParagraph || !ro.attached) continue;
      final local = ro.globalToLocal(global);
      if (local.dx < -8 || local.dy < -6 || local.dx > ro.size.width + 8 || local.dy > ro.size.height + 6) continue;
      return LyricHit(widget.pieces[i], ro.getPositionForOffset(local).offset);
    }
    return null;
  }

  static FontWeight _heavier(FontWeight w) => FontWeight.values.firstWhere((x) => x.value >= (w.value + 200).clamp(100, 900));

  TextStyle _style(LyricPiece p, double scale) {
    final body = widget.type.body(color: widget.theme.text, scale: scale, shadows: widget.theme.textShadows);
    if (p.level <= 1) return body;
    // Emphasis: same size, a warmer/brighter tone and a heavier weight.
    return body.copyWith(color: widget.theme.emphasis, fontWeight: _heavier(body.fontWeight ?? FontWeight.w400));
  }

  TextAlign _textAlign(int i) => switch (widget.align) {
        LyricAlign.centered => TextAlign.center,
        LyricAlign.left => TextAlign.start,
        LyricAlign.staggered => i.isEven ? TextAlign.start : TextAlign.end,
      };

  double _gap(LyricPiece p, double fontSize) => p.newBlock ? fontSize * 0.9 : fontSize * 0.34;

  InlineSpan _span(LyricPiece p, TextStyle style) {
    final text = p.text;
    final highlight = widget.highlightColor(p.sid);
    final base = highlight == null ? style : style.copyWith(backgroundColor: highlight);
    if (widget.hardWords.isEmpty) return TextSpan(text: text, style: base);
    final parts = <InlineSpan>[];
    var last = 0;
    for (final m in RegExp(r"[A-Za-z][A-Za-z'’\-]*").allMatches(text)) {
      if (!widget.hardWords.contains(m.group(0)!.toLowerCase())) continue;
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
    return TextSpan(style: base, children: parts);
  }

  InlineSpan _spotSpan(double size) {
    final p = widget.pieces.first;
    final text = p.text;
    final f = widget.focus ?? (start: 0, end: text.length);
    final focus = widget.type.display(color: widget.theme.spot, size: size, shadows: widget.theme.textShadows);
    final rest = focus.copyWith(color: widget.theme.text.withValues(alpha: 0.84));
    final highlight = widget.highlightColor(p.sid);
    TextStyle bg(TextStyle s) => highlight == null ? s : s.copyWith(backgroundColor: highlight);
    return TextSpan(children: [
      if (f.start > 0) TextSpan(text: text.substring(0, f.start), style: bg(rest)),
      TextSpan(text: text.substring(f.start, f.end), style: bg(focus)),
      if (f.end < text.length) TextSpan(text: text.substring(f.end), style: bg(rest)),
    ]);
  }

  double _measure(InlineSpan span, TextAlign align, double maxW, TextScaler scaler) {
    final tp = TextPainter(text: span, textAlign: align, textDirection: TextDirection.ltr, textScaler: scaler)..layout(maxWidth: maxW);
    final h = tp.height;
    tp.dispose();
    return h;
  }

  void _fitRegular(double maxW, double maxH, TextScaler scaler) {
    double height(double scale) {
      var total = 0.0;
      for (var i = 0; i < widget.pieces.length; i++) {
        final p = widget.pieces[i];
        final style = _style(p, scale);
        total += _measure(TextSpan(text: p.text, style: style), _textAlign(i), maxW, scaler) + (i == 0 ? 0 : _gap(p, style.fontSize!));
      }
      return total;
    }

    for (final scale in const [1.0, 0.94, 0.88, 0.82]) {
      if (height(scale) <= maxH) {
        _fit = scale;
        _overflows = false;
        return;
      }
    }
    _fit = 0.82;
    _overflows = true;
  }

  void _fitSpotlight(double maxW, double maxH, TextScaler scaler) {
    final base = widget.type.settings.fontSize;
    final cap = (base * 1.75).clamp(28.0, 44.0);
    final floor = (base * 1.15).clamp(20.0, 30.0);
    // Keep air around the line: it should float, not fill.
    final room = maxH * 0.72;
    double height(double size) => _measure(_spotSpan(size), TextAlign.center, maxW, scaler);
    if (height(cap) <= room) {
      _fit = cap;
      _overflows = false;
      return;
    }
    var lo = floor, hi = cap;
    for (var k = 0; k < 8; k++) {
      final mid = (lo + hi) / 2;
      if (height(mid) <= room) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    _fit = lo;
    _overflows = height(lo) > maxH;
  }

  @override
  void didUpdateWidget(ReelText old) {
    super.didUpdateWidget(old);
    if (!identical(old.pieces, widget.pieces) || old.type.bodyFamily != widget.type.bodyFamily || old.spotlight != widget.spotlight) {
      _fitKey = null;
    }
  }

  Widget _scrollable(Widget column) => NotificationListener<ScrollNotification>(
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
        child: SingleChildScrollView(physics: const ClampingScrollPhysics(), child: column),
      );

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final fullText = widget.pieces.map((p) => p.text).join(' ');
    return LayoutBuilder(builder: (context, constraints) {
      final key = (constraints.maxWidth, constraints.maxHeight, scaler, widget.type.settings.fontSize, widget.spotlight);
      if (_fitKey != key) {
        _fitKey = key;
        widget.spotlight
            ? _fitSpotlight(constraints.maxWidth, constraints.maxHeight, scaler)
            : _fitRegular(constraints.maxWidth, constraints.maxHeight, scaler);
      }
      while (_keys.length < widget.pieces.length) {
        _keys.add(GlobalKey());
      }
      final Widget column = widget.spotlight ? _spotlight(scaler) : _lines(scaler);
      return Semantics(
        label: fullText,
        child: ExcludeSemantics(child: _overflows ? _scrollable(column) : Center(child: column)),
      );
    });
  }

  Widget _lines(TextScaler scaler) {
    final n = widget.pieces.length;
    final stagger = n <= 1 ? 0.0 : (0.5 / (n - 1)).clamp(0.0, 0.1);
    final lines = <Widget>[];
    for (var i = 0; i < n; i++) {
      final p = widget.pieces[i];
      final style = _style(p, _fit);
      final local = ((widget.progress - i * stagger) / 0.5).clamp(0.0, 1.0);
      final eased = Curves.easeOutCubic.transform(local);
      if (i > 0) lines.add(SizedBox(height: _gap(p, style.fontSize!)));
      lines.add(Opacity(
        opacity: eased,
        child: Transform.translate(
          offset: Offset(0, (1 - eased) * 12),
          child: SizedBox(
            width: double.infinity,
            child: Text.rich(_span(p, style), key: _keys[i], textAlign: _textAlign(i), textScaler: scaler),
          ),
        ),
      ));
    }
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: lines);
  }

  Widget _spotlight(TextScaler scaler) {
    final e = Curves.easeOutCubic.transform(widget.progress.clamp(0.0, 1.0));
    final bar = Curves.easeOutCubic.transform(((widget.progress - 0.3) / 0.7).clamp(0.0, 1.0));
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 34 * bar,
        height: 3,
        decoration: BoxDecoration(color: widget.theme.accent, borderRadius: BorderRadius.circular(2)),
      ),
      SizedBox(height: _fit * 0.75),
      Opacity(
        opacity: e,
        child: Transform.scale(
          scale: 0.95 + 0.05 * e,
          child: SizedBox(
            width: double.infinity,
            child: Text.rich(_spotSpan(_fit), key: _keys[0], textAlign: TextAlign.center, textScaler: scaler),
          ),
        ),
      ),
    ]);
  }
}

class _BookRow extends StatelessWidget {
  const _BookRow({
    required this.title,
    required this.subtitle,
    required this.ink,
    required this.accent,
    required this.shadows,
    this.coverPath,
  });

  final String title;
  final String subtitle;
  final Color ink;
  final Color accent;
  final List<Shadow>? shadows;
  final String? coverPath;

  @override
  Widget build(BuildContext context) {
    final cover = coverPath != null && File(coverPath!).existsSync() ? FileImage(File(coverPath!)) : null;
    final initials = title.trim().isEmpty ? '📖' : title.trim()[0].toUpperCase();
    final shadow = shadows;
    return Row(children: [
      Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [accent, accent.withValues(alpha: 0.4)])),
        child: CircleAvatar(
          radius: 18,
          backgroundColor: const Color(0xFF2F3A35),
          backgroundImage: cover,
          child: cover == null
              ? Text(initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontFamily: 'Literata'))
              : null,
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: ink, fontWeight: FontWeight.w800, fontSize: 15, shadows: shadow)),
          Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: ink.withValues(alpha: 0.8), fontSize: 12.5, shadows: shadow)),
        ]),
      ),
    ]);
  }
}

class _ActionRail extends StatelessWidget {
  const _ActionRail({
    required this.ink,
    required this.accent,
    required this.shadows,
    required this.liked,
    required this.saved,
    required this.listening,
    required this.onLike,
    required this.onSave,
    required this.onNote,
    required this.onShare,
    required this.onListen,
  });

  final Color ink;
  final Color accent;
  final List<Shadow>? shadows;
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
    Widget b(IconData icon, String label, String tooltip, VoidCallback onTap, {Color? color, bool active = false}) => _RailButton(
          icon: icon,
          label: label,
          tooltip: tooltip,
          color: color ?? ink,
          shadows: shadows,
          active: active,
          onTap: onTap,
        );
    return Column(mainAxisSize: MainAxisSize.min, children: [
      b(liked ? Icons.favorite : Icons.favorite_border, liked ? 'Liked' : 'Like', liked ? 'Unlike' : 'Like', onLike,
          color: liked ? const Color(0xFFFF5A79) : null, active: liked),
      b(saved ? Icons.bookmark : Icons.bookmark_border, saved ? 'Saved' : 'Save', saved ? 'Saved' : 'Save', onSave,
          color: saved ? accent : null, active: saved),
      b(Icons.edit_note, 'Note', 'Highlight & note', onNote),
      b(Icons.ios_share, 'Share', 'Share', onShare),
      b(listening ? Icons.stop_circle_outlined : Icons.headphones_outlined, listening ? 'Stop' : 'Listen',
          listening ? 'Stop reading aloud' : 'Read aloud', onListen,
          color: listening ? accent : null, active: listening),
    ]);
  }
}

/// Icon + label with a springy pop when it becomes active.
class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.color,
    required this.shadows,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final Color color;
  final List<Shadow>? shadows;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final shadow = shadows;
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 30,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TweenAnimationBuilder<double>(
              key: ValueKey(active),
              tween: Tween(begin: active ? 0.55 : 1, end: 1),
              duration: const Duration(milliseconds: 420),
              curve: Curves.elasticOut,
              builder: (context, v, child) => Transform.scale(scale: v, child: child),
              child: Icon(icon, color: color, size: 31, shadows: shadow),
            ),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w700, shadows: shadow)),
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
