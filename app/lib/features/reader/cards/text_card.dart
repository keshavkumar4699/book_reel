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
import 'lyric_layout.dart';

/// A sentence resolved for rendering.
class CardSentence {
  const CardSentence(this.sentence, this.block, {required this.firstInBlock});
  final Sentence sentence;
  final Block block;
  final bool firstInBlock;
}

/// A text card shown full-screen like a reel with lyric-style typography:
/// the author's words split into lines, important phrases (chosen by the AI
/// on paid tiers) much larger, lines animating in one after another.
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
  final String? coverPath;

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> with TickerProviderStateMixin {
  final _lyricKey = GlobalKey<_LyricTextState>();
  late final AnimationController _reveal = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  late final AnimationController _flash = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
  String? _flashSid;
  final List<_Burst> _bursts = [];
  double _dragDx = 0;
  Offset? _doubleTapAt;
  bool _revealed = false;
  late List<LyricPiece> _pieces;
  late LyricAlign _align;

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
    if (!identical(old.card, widget.card) || old.sentences.length != widget.sentences.length) _buildPieces();
    if (widget.active && !_revealed) _startReveal();
  }

  void _buildPieces() {
    _pieces = buildLyricPieces(
      [for (final s in widget.sentences) (sid: s.sentence.id, text: s.sentence.text, block: s.block.index, type: s.block.type)],
      emphasis: widget.card.emphasis,
      keySids: widget.card.keySids.toSet(),
      // Cards that went through AI art direction always carry a layout.
      aiDirected: widget.card.layout != null,
    );
    _align = lyricAlignFor(widget.card.layout, _pieces);
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
    final hit = _lyricKey.currentState?.hitTest(d.globalPosition);
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
    final hit = _lyricKey.currentState?.hitTest(d.globalPosition);
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
    if (!widget.settings.underlineHardWords) return const {};
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
    final onScene = t.glass.a > 0;
    final padding = MediaQuery.paddingOf(context);
    final leftHanded = widget.settings.leftHanded;
    const railWidth = 72.0;
    final reveal = (_dragDx.abs() / _swipeTrigger).clamp(0.0, 1.0);
    final ink = onScene ? Colors.white : t.text;
    // On paper the accent must stay readable as text.
    final accent = onScene ? widget.accent : const Color(0xFFA8551A);

    final lyric = LyricText(
      key: _lyricKey,
      pieces: _pieces,
      align: _align,
      progress: _reveal.value,
      settings: widget.settings,
      textColor: onScene ? const Color(0xF2FFFFFF) : t.text,
      accent: accent,
      shadows: onScene,
      hardWords: _hardWordsLower,
      underlineColor: t.hardWordUnderline,
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
        // Legibility: a soft shade over the scene, darker where the text is.
        if (onScene)
          const Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x59000000), Color(0x73000000), Color(0x80000000), Color(0xA6000000)],
                    stops: [0, 0.35, 0.7, 1],
                  ),
                ),
              ),
            ),
          ),
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
        // The text fills the screen between the top bar and the book row.
        Positioned(
          top: padding.top + 70,
          bottom: padding.bottom + 86,
          left: leftHanded ? railWidth : 22,
          right: leftHanded ? 22 : railWidth,
          child: Transform.translate(offset: Offset(_dragDx * 0.6, 0), child: lyric),
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
            ink: ink,
            accent: widget.accent,
            shadows: onScene,
          ),
        ),
        // Action rail (bottom-right; mirrored for left-handed readers).
        Positioned(
          right: leftHanded ? null : 4,
          left: leftHanded ? 4 : null,
          bottom: padding.bottom + 16,
          width: railWidth - 8,
          child: _ActionRail(
            ink: ink,
            accent: widget.accent,
            shadows: onScene,
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

/// Lays out lyric pieces to fill the available box: a size search finds the
/// largest base size at which every line fits, so short cards get big text.
class LyricText extends StatefulWidget {
  const LyricText({
    super.key,
    required this.pieces,
    required this.align,
    required this.progress,
    required this.settings,
    required this.textColor,
    required this.accent,
    required this.shadows,
    required this.hardWords,
    required this.underlineColor,
    required this.highlightColor,
    required this.onOverscroll,
  });

  final List<LyricPiece> pieces;
  final LyricAlign align;

  /// Entrance animation progress, 0–1.
  final double progress;
  final AppSettings settings;
  final Color textColor;
  final Color accent;
  final bool shadows;
  final Set<String> hardWords;
  final Color underlineColor;
  final Color? Function(String sid) highlightColor;
  final void Function(int direction) onOverscroll;

  @override
  State<LyricText> createState() => _LyricTextState();
}

class LyricHit {
  const LyricHit(this.piece, this.offset);
  final LyricPiece piece;

  /// Character offset within the piece's text.
  final int offset;
}

class _LyricTextState extends State<LyricText> {
  final List<GlobalKey> _keys = [];
  double _overscroll = 0;
  (double, double, double, TextScaler)? _fitKey;
  double _fitBase = 22;
  bool _overflows = false;

  static const _shadows = [
    Shadow(color: Color(0x8C000000), blurRadius: 18),
    Shadow(color: Color(0x66000000), blurRadius: 3, offset: Offset(0, 1)),
  ];

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

  TextStyle _style(LyricPiece p, double base) {
    final s = widget.settings;
    final shadows = widget.shadows ? _shadows : null;
    switch (p.level) {
      case 3:
        return TextStyle(
          fontFamily: 'AtkinsonHyperlegible',
          fontSize: base * levelScale(3),
          fontWeight: FontWeight.w800,
          height: 1.06,
          letterSpacing: -0.4,
          color: widget.accent,
          shadows: shadows,
        );
      case 2:
        return TextStyle(
          fontFamily: 'Literata',
          fontStyle: FontStyle.italic,
          fontSize: base * levelScale(2),
          fontWeight: FontWeight.w600,
          height: 1.16,
          color: widget.textColor,
          shadows: shadows,
        );
      default:
        return TextStyle(
          fontFamily: fontFamilyFor(s.font),
          fontSize: base,
          fontWeight: FontWeight.w500,
          height: 1.3,
          letterSpacing: s.letterSpacing,
          wordSpacing: s.wordSpacing,
          color: widget.textColor.withValues(alpha: widget.textColor.a * 0.94),
          shadows: shadows,
        );
    }
  }

  String _display(LyricPiece p) => p.level == 3 && p.text.split(RegExp(r'\s+')).length <= 4 ? p.text.toUpperCase() : p.text;

  TextAlign _textAlign(int i) => switch (widget.align) {
        LyricAlign.centered => TextAlign.center,
        LyricAlign.left => TextAlign.start,
        LyricAlign.staggered => i.isEven ? TextAlign.start : TextAlign.end,
      };

  double _gap(LyricPiece p, double base) => p.newBlock ? base * 0.75 : base * 0.3;

  /// Largest base size (within the reader's limits) at which all lines fit.
  void _fit(double maxW, double maxH, TextScaler scaler) {
    final key = (maxW, maxH, widget.settings.fontSize, scaler);
    if (_fitKey == key) return;
    _fitKey = key;
    final cap = (widget.settings.fontSize * 1.9).clamp(26.0, 56.0);
    const floor = 15.0;
    double height(double base) {
      var total = 0.0;
      for (var i = 0; i < widget.pieces.length; i++) {
        final p = widget.pieces[i];
        final tp = TextPainter(
          text: TextSpan(text: _display(p), style: _style(p, base)),
          textAlign: _textAlign(i),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
        )..layout(maxWidth: maxW);
        total += tp.height + (i == 0 ? 0 : _gap(p, base));
        tp.dispose();
      }
      return total;
    }

    if (height(cap) <= maxH) {
      _fitBase = cap;
      _overflows = false;
      return;
    }
    var lo = floor, hi = cap;
    for (var k = 0; k < 9; k++) {
      final mid = (lo + hi) / 2;
      if (height(mid) <= maxH) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    _fitBase = lo;
    _overflows = height(lo) > maxH;
  }

  @override
  void didUpdateWidget(LyricText old) {
    super.didUpdateWidget(old);
    if (!identical(old.pieces, widget.pieces) || old.settings.font != widget.settings.font) _fitKey = null;
  }

  InlineSpan _span(LyricPiece p, TextStyle style) {
    final text = _display(p);
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
          decorationColor: widget.underlineColor,
          decorationThickness: 2,
        ),
      ));
      last = m.end;
    }
    if (last < text.length) parts.add(TextSpan(text: text.substring(last)));
    return TextSpan(style: base, children: parts);
  }

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final fullText = widget.pieces.map((p) => p.text).join(' ');
    return LayoutBuilder(builder: (context, constraints) {
      _fit(constraints.maxWidth, constraints.maxHeight, scaler);
      while (_keys.length < widget.pieces.length) {
        _keys.add(GlobalKey());
      }
      final base = _fitBase;
      final n = widget.pieces.length;
      final stagger = n <= 1 ? 0.0 : (0.55 / (n - 1)).clamp(0.0, 0.12);
      final lines = <Widget>[];
      for (var i = 0; i < n; i++) {
        final p = widget.pieces[i];
        final style = _style(p, base);
        final local = ((widget.progress - i * stagger) / 0.45).clamp(0.0, 1.0);
        final eased = Curves.easeOutCubic.transform(local);
        final scale = p.level == 3 ? 1.0 + (1 - Curves.easeOutBack.transform(local)) * 0.18 : 1.0;
        if (i > 0) lines.add(SizedBox(height: _gap(p, base)));
        lines.add(Opacity(
          opacity: eased,
          child: Transform.translate(
            offset: Offset(0, (1 - eased) * 18),
            child: Transform.scale(
              scale: scale,
              alignment: switch (_textAlign(i)) {
                TextAlign.center => Alignment.center,
                TextAlign.end => Alignment.centerRight,
                _ => Alignment.centerLeft,
              },
              child: SizedBox(
                width: double.infinity,
                child: Text.rich(_span(p, style), key: _keys[i], textAlign: _textAlign(i), textScaler: scaler),
              ),
            ),
          ),
        ));
      }
      final column = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: lines,
      );
      return Semantics(
        label: fullText,
        child: ExcludeSemantics(
          child: _overflows
              ? NotificationListener<ScrollNotification>(
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
                )
              : Center(child: column),
        ),
      );
    });
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
  final bool shadows;
  final String? coverPath;

  @override
  Widget build(BuildContext context) {
    final cover = coverPath != null && File(coverPath!).existsSync() ? FileImage(File(coverPath!)) : null;
    final initials = title.trim().isEmpty ? '📖' : title.trim()[0].toUpperCase();
    final shadow = shadows ? const [Shadow(color: Color(0x99000000), blurRadius: 8)] : null;
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
  final bool shadows;
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
  final bool shadows;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final shadow = shadows ? const [Shadow(color: Color(0x99000000), blurRadius: 10)] : null;
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
