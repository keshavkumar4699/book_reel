import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../../core/models/book.dart';
import '../../../core/models/reel_card.dart';
import '../../../core/parsing/block_builder.dart';
import '../../../core/text/lexicon.dart';
import '../../../data/notebook.dart';
import '../../../data/settings.dart';
import '../../../ui/kit.dart';
import '../../../ui/theme.dart';
import '../../../ui/typography.dart';
import '../../../ui/widgets.dart';
import '../../../core/text/lyric_layout.dart';

/// A place in the book: a sentence and a character offset in it.
typedef _Pos = ({String sid, int off});

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
    required this.highlightsIn,
    required this.onCreateHighlight,
    required this.onSaveHighlight,
    required this.onRemoveHighlight,
    required this.onNoteHighlight,
    required this.onSelecting,
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
  /// Highlights that touch a sentence.
  final List<Highlight> Function(String sid) highlightsIn;

  /// Highlights a whole sentence (a tap on unhighlighted text).
  final Highlight Function(Sentence sentence) onCreateHighlight;

  /// Saves an adjusted highlight, replacing those it was merged with.
  final void Function(Highlight highlight, Set<String> absorbed) onSaveHighlight;
  final void Function(String id) onRemoveHighlight;
  final void Function(Highlight highlight) onNoteHighlight;

  /// A highlight is being adjusted (the reader holds the page still).
  final void Function(bool active) onSelecting;
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
  final List<_Burst> _bursts = [];

  /// The highlight being adjusted with its handles (a working copy).
  Highlight? _edit;

  /// While a handle is dragged: the other end of the range, which stays put.
  _Pos? _fixed;

  /// The selection's extent on this card, for placing the toolbar.
  Rect? _selRect;

  /// Horizontal drag; only the text and the swipe hint follow it.
  final _dx = ValueNotifier<double>(0);
  Offset? _doubleTapAt;
  bool _revealed = false;
  late List<LyricPiece> _pieces;
  late LyricAlign _align;
  ({int start, int end})? _focus;

  /// Hard words to underline, worked out once per reel (not on every frame).
  Set<String> _hardWords = const {};
  Object? _hardWordsKey;

  @override
  void initState() {
    super.initState();
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
    // Leaving the reel (e.g. a jump from the contents) finishes the edit.
    if (!widget.active && _edit != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !widget.active && _edit != null) _commit();
      });
    }
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
    _dx.dispose();
    _reveal.dispose();
    _flash.dispose();
    for (final b in _bursts) {
      b.controller.dispose();
    }
    super.dispose();
  }

  Sentence? _sentence(String sid) => widget.sentences.where((s) => s.sentence.id == sid).firstOrNull?.sentence;

  // ------------------------------------------------------------- gestures

  /// Tap on text: highlight its sentence and show handles to adjust it, or
  /// pick up an existing highlight. While adjusting, a tap elsewhere is done.
  void _onTapUp(TapUpDetails d) {
    final hit = _textKey.currentState?.hitTest(d.globalPosition);
    final edit = _edit;
    if (edit != null) {
      if (hit != null && _covers(edit, hit.piece.sid, hit.piece.start + hit.offset)) return;
      _commit();
      return;
    }
    if (hit == null) return;
    final sentence = _sentence(hit.piece.sid);
    if (sentence == null || sentence.text == sceneBreakMarker) return;
    HapticFeedback.selectionClick();
    final at = hit.piece.start + hit.offset;
    final existing = widget.highlightsIn(sentence.id).where((h) => _covers(h, sentence.id, at)).firstOrNull;
    final fresh = existing == null;
    setState(() => _edit = existing ?? widget.onCreateHighlight(sentence));
    widget.onSelecting(true);
    if (fresh) _flash.forward(from: 0);
  }

  int _length(String sid) => _sentence(sid)?.text.length ?? 0;

  bool _covers(Highlight h, String sid, int offset) {
    final span = h.spanIn(sid, _length(sid));
    return span != null && offset >= span.from && offset <= span.to;
  }

  _Pos _startOf(Highlight h) => (sid: h.sid, off: h.start ?? 0);

  /// A last sentence that is not on this reel counts as running to its end.
  _Pos _endOf(Highlight h) => (sid: h.lastSid, off: h.end ?? (_sentence(h.lastSid)?.text.length ?? 1 << 30));

  static int _cmp(_Pos a, _Pos b) {
    final c = compareSids(a.sid, b.sid);
    return c != 0 ? c : a.off - b.off;
  }

  static bool _space(int c) => c == 0x20 || c == 0x0A || c == 0x09 || c == 0xA0;

  /// Snaps to the start of the word at [i] (or the next word after spaces).
  static int _wordStart(String t, int i) {
    if (i < t.length && _space(t.codeUnitAt(i))) {
      while (i < t.length && _space(t.codeUnitAt(i))) {
        i++;
      }
      return i;
    }
    while (i > 0 && !_space(t.codeUnitAt(i - 1))) {
      i--;
    }
    return i;
  }

  /// Snaps to the end of the word at [i] (or the previous word before spaces).
  static int _wordEnd(String t, int i) {
    if (i > 0 && _space(t.codeUnitAt(i - 1))) {
      while (i > 0 && _space(t.codeUnitAt(i - 1))) {
        i--;
      }
      return i;
    }
    while (i < t.length && !_space(t.codeUnitAt(i))) {
      i++;
    }
    return i;
  }

  /// The words a highlight covers on this reel.
  String _textOf(Highlight h) => [
        for (final s in widget.sentences)
          if (h.spanIn(s.sentence.id, s.sentence.text.length) case final span?) s.sentence.text.substring(span.from, span.to),
      ].join(' ');

  void _onHandleDrag(bool startHandle, Offset global) {
    final h = _edit;
    final reel = _textKey.currentState;
    if (h == null || reel == null) return;
    final fixed = _fixed ??= startHandle ? _endOf(h) : _startOf(h);
    final hit = reel.hitTestNearest(global);
    if (hit == null) return;
    final sid = hit.piece.sid;
    final text = _sentence(sid)?.text;
    if (text == null || text == sceneBreakMarker) return;
    final raw = (hit.piece.start + hit.offset).clamp(0, text.length);
    // The dragged handle may cross the other one: it then becomes the other end.
    final before = _cmp((sid: sid, off: raw), fixed) < 0;
    final moving = (sid: sid, off: before ? _wordStart(text, raw) : _wordEnd(text, raw));
    final (start, end) = before ? (moving, fixed) : (fixed, moving);
    if (_cmp(start, end) >= 0) return;
    if (_cmp(start, _startOf(h)) == 0 && _cmp(end, _endOf(h)) == 0) return;
    HapticFeedback.selectionClick();
    final next = h.withRange(sid: start.sid, endSid: end.sid, start: start.off, end: end.off, text: h.text);
    setState(() => _edit = next.copyWith(text: _textOf(next)));
  }

  bool _overlaps(Highlight a, Highlight b) => _cmp(_startOf(a), _endOf(b)) < 0 && _cmp(_startOf(b), _endOf(a)) < 0;

  /// Saves the adjusted highlight, merged with any it now overlaps.
  Highlight? _commit() {
    final h = _edit;
    if (h == null) return null;
    var merged = h;
    final absorbed = <String>{};
    for (final s in widget.sentences) {
      for (final other in widget.highlightsIn(s.sentence.id)) {
        if (other.id == h.id || absorbed.contains(other.id) || !_overlaps(merged, other)) continue;
        final start = _cmp(_startOf(merged), _startOf(other)) <= 0 ? _startOf(merged) : _startOf(other);
        final end = _cmp(_endOf(merged), _endOf(other)) >= 0 ? _endOf(merged) : _endOf(other);
        final notes = [merged.note, other.note].whereType<String>().where((n) => n.isNotEmpty).join('\n');
        merged = merged.withRange(sid: start.sid, endSid: end.sid, start: start.off, end: end.off, text: merged.text);
        if (notes.isNotEmpty) merged = merged.copyWith(note: notes);
        absorbed.add(other.id);
      }
    }
    merged = merged.copyWith(text: _textOf(merged));
    setState(() {
      _edit = null;
      _fixed = null;
      _selRect = null;
    });
    widget.onSaveHighlight(merged, absorbed);
    widget.onSelecting(false);
    return merged;
  }

  void _removeEdit() {
    final h = _edit;
    if (h == null) return;
    setState(() {
      _edit = null;
      _fixed = null;
      _selRect = null;
    });
    widget.onRemoveHighlight(h.id);
    widget.onSelecting(false);
  }

  void _onSelectionGeometry(Rect? start, Rect? end) {
    final box = context.findRenderObject() as RenderBox?;
    Rect? next;
    if (box != null && box.hasSize && start != null && end != null) {
      final top = box.globalToLocal(start.topLeft).dy, bottom = box.globalToLocal(end.bottomLeft).dy;
      next = Rect.fromLTRB(0, top, box.size.width, bottom);
    }
    if (next != _selRect && mounted) setState(() => _selRect = next);
  }

  /// Highlighted stretches per line, with the one being adjusted on top.
  List<List<LineMark>> _marks() {
    final colors = widget.theme.highlights;
    LineMark? mark(LyricPiece p, Highlight h, {required bool editing}) {
      final span = h.spanIn(p.sid, _length(p.sid));
      if (span == null) return null;
      final from = math.max(span.from, p.start) - p.start, to = math.min(span.to, p.end) - p.start;
      if (to <= from) return null;
      return LineMark(from.clamp(0, p.text.length), to.clamp(0, p.text.length), colors[h.color % highlightColorCount], editing: editing);
    }

    final edit = _edit;
    return [
      for (final p in _pieces)
        [
          for (final h in widget.highlightsIn(p.sid))
            if (h.id != edit?.id) ?mark(p, h, editing: false),
          if (edit != null) ?mark(p, edit, editing: true),
        ],
    ];
  }

  /// Handle positions: the first and last line the adjusted highlight covers.
  LineSelection? _selection(List<List<LineMark>> marks) {
    int? startLine, endLine;
    var startOffset = 0, endOffset = 0;
    for (var i = 0; i < marks.length; i++) {
      for (final m in marks[i]) {
        if (!m.editing) continue;
        if (startLine == null) {
          startLine = i;
          startOffset = m.from;
        }
        endLine = i;
        endOffset = m.to;
      }
    }
    if (startLine == null || endLine == null) return null;
    return (startLine: startLine, startOffset: startOffset, endLine: endLine, endOffset: endOffset);
  }

  static const _colorNames = ['Amber', 'Green', 'Blue', 'Pink'];

  Widget _toolbar() {
    final kit = Kit.of(context);
    final h = _edit!;
    Widget action(IconData icon, String label, VoidCallback onTap) =>
        KitIconButton(icon: icon, semanticLabel: label, onPressed: onTap, glass: false, size: 34, iconSize: 21);
    return Material(
      type: MaterialType.transparency,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: kit.sheet,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: kit.stroke),
          boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 16, offset: Offset(0, 5))],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < highlightColorCount; i++)
            KitPressable(
              onTap: () => setState(() => _edit = _edit!.copyWith(color: i)),
              semanticLabel: '${_colorNames[i]} highlight',
              selected: h.color == i,
              excludeSemantics: true,
              child: Container(
                width: 26,
                height: 26,
                margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 11),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.theme.highlights[i].withValues(alpha: 1),
                  border: Border.all(color: h.color == i ? kit.ink : const Color(0x00000000), width: 2.5),
                ),
              ),
            ),
          Container(width: 1, height: 26, margin: const EdgeInsets.symmetric(horizontal: 4), color: kit.stroke),
          action(Icons.edit_note_rounded, 'Add note', () {
            final saved = _commit();
            if (saved != null) widget.onNoteHighlight(saved);
          }),
          action(Icons.copy_rounded, 'Copy', () {
            Clipboard.setData(ClipboardData(text: h.text));
            showKitToast(context, 'Copied', icon: Icons.check_rounded);
          }),
          action(Icons.delete_outline_rounded, 'Remove highlight', _removeEdit),
          action(Icons.check_rounded, 'Done', _commit),
        ]),
      ),
    );
  }

  void _onDoubleTap() {
    HapticFeedback.mediumImpact();
    if (!widget.liked) widget.onLike();
    final at = _doubleTapAt;
    final box = context.findRenderObject() as RenderBox?;
    if (at == null || box == null) return;
    final burst = _Burst(box.globalToLocal(at), AnimationController(vsync: this, duration: const Duration(milliseconds: 750)));
    burst.controller
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
    final dx = _dx.value;
    _dx.value = 0;
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
    final key = (widget.card, widget.sentences.length, widget.spotlight, widget.settings.underlineHardWords,
        widget.settings.readingLevel, widget.lexicon);
    if (key == _hardWordsKey) return _hardWords;
    _hardWordsKey = key;
    return _hardWords = _findHardWords();
  }

  Set<String> _findHardWords() {
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
    // The text never fills the screen: the scene shows above and below it.
    final zone = reelTextInsets(screen: screen, topInset: padding.top, bottomInset: padding.bottom);

    final marks = _marks();
    final text = ReelText(
      key: _textKey,
      pieces: _pieces,
      align: _align,
      spotlight: widget.spotlight,
      focus: _focus,
      reveal: _reveal,
      flash: _flash,
      type: widget.type,
      theme: t,
      hardWords: _hardWordsLower,
      marks: marks,
      selection: _selection(marks),
      onHandleDrag: _onHandleDrag,
      onHandleDragEnd: () => _fixed = null,
      onSelectionGeometry: _onSelectionGeometry,
      onOverscroll: widget.onOverscroll,
    );
    final editing = _edit != null;
    // The toolbar floats above the highlight, or below it near the top.
    final sel = _selRect;
    final toolbarTop = sel == null ? null : (sel.top - 64 > padding.top + 70 ? sel.top - 64 : sel.bottom + 16);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: _onTapUp,
      // While a highlight is adjusted, taps only place or finish it.
      onDoubleTapDown: editing ? null : (d) => _doubleTapAt = d.globalPosition,
      onDoubleTap: editing ? null : _onDoubleTap,
      onLongPressStart: editing ? null : _onLongPress,
      onHorizontalDragUpdate: editing ? null : (d) => _dx.value = (_dx.value + d.delta.dx).clamp(-120.0, 120.0),
      onHorizontalDragEnd: editing ? null : _onDragEnd,
      child: Stack(children: [
        ValueListenableBuilder<double>(
          valueListenable: _dx,
          builder: (context, dx, _) {
            if (dx == 0) return const SizedBox.shrink();
            final reveal = (dx.abs() / _swipeTrigger).clamp(0.0, 1.0);
            return Positioned.fill(
              child: Align(
                alignment: dx < 0 ? Alignment.centerRight : Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: Opacity(
                    opacity: reveal,
                    child: _SwipeHint(
                      icon: dx < 0
                          ? Icon(widget.saved ? Icons.bookmark_remove_rounded : Icons.bookmark_add_rounded, color: Colors.white)
                          : const ShareArrowIcon(color: Colors.white),
                      label: dx < 0 ? (widget.saved ? 'Unsave' : 'Save') : 'Share',
                      color: const Color(0xCC111111),
                      armed: reveal >= 1,
                    ),
                  ),
                ),
              ),
            );
          },
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
              child: ValueListenableBuilder<double>(
                valueListenable: _dx,
                builder: (context, dx, child) => Transform.translate(offset: Offset(dx * 0.6, 0), child: child),
                // Its own layer: the scene moving behind never repaints the text.
                child: RepaintBoundary(child: text),
              ),
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
        for (final b in _bursts) _HeartBurstView(burst: b, color: ember),
        if (editing && toolbarTop != null)
          Positioned(left: 8, right: 8, top: toolbarTop, child: Center(child: _toolbar())),
      ]),
    );
  }
}

/// A highlighted stretch of one display line (offsets within the line's text).
class LineMark {
  const LineMark(this.from, this.to, this.color, {this.editing = false});
  final int from;
  final int to;
  final Color color;

  /// The highlight being adjusted (it fades in when new).
  final bool editing;
}

/// Where a selection's handles sit: line index and offset in that line.
typedef LineSelection = ({int startLine, int startOffset, int endLine, int endOffset});

class _HandleDrag extends Drag {
  _HandleDrag({required this.onUpdate, required this.onEnd});
  final ValueChanged<Offset> onUpdate;
  final VoidCallback onEnd;

  @override
  void update(DragUpdateDetails details) => onUpdate(details.globalPosition);

  @override
  void end(DragEndDetails details) => onEnd();

  @override
  void cancel() => onEnd();
}

class _HandlePainter extends CustomPainter {
  _HandlePainter({required this.color, required this.start, required this.caretHeight});
  final Color color;
  final bool start;
  final double caretHeight;

  @override
  void paint(Canvas canvas, Size size) {
    const knob = 7.0;
    final x = size.width / 2 + 1;
    final top = start ? size.height - caretHeight : 0.0;
    final paint = Paint()..color = color;
    canvas.drawRRect(RRect.fromLTRBR(x - 1.25, top, x + 1.25, top + caretHeight, const Radius.circular(1.25)), paint);
    final knobY = start ? top - knob + 1 : top + caretHeight + knob - 1;
    canvas.drawCircle(Offset(x, knobY), knob + 1.5, Paint()..color = const Color(0x40000000));
    canvas.drawCircle(Offset(x, knobY), knob, paint);
  }

  @override
  bool shouldRepaint(_HandlePainter old) => old.color != color || old.start != start || old.caretHeight != caretHeight;
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
    required this.reveal,
    required this.type,
    required this.theme,
    required this.hardWords,
    required this.onOverscroll,
    this.marks = const [],
    this.selection,
    this.onHandleDrag,
    this.onHandleDragEnd,
    this.onSelectionGeometry,
    this.spotlight = false,
    this.focus,
    this.flash,
  });

  final List<LyricPiece> pieces;
  final LyricAlign align;

  /// Entrance animation, 0–1. Lines fade and rise in with it; it only moves
  /// layers, so the text is laid out once.
  final Animation<double> reveal;

  /// A highlight that was just added fades in with this.
  final Animation<double>? flash;
  final BookType type;
  final ReadingTheme theme;
  final Set<String> hardWords;
  final void Function(int direction) onOverscroll;

  /// Highlighted stretches, per line.
  final List<List<LineMark>> marks;

  /// The highlight being adjusted: its handles sit at these lines and offsets.
  final LineSelection? selection;

  /// A handle was dragged: [start] tells which, [global] is where its caret
  /// should go.
  final void Function(bool start, Offset global)? onHandleDrag;
  final VoidCallback? onHandleDragEnd;

  /// Where the selection's first and last carets are on screen (global).
  final void Function(Rect? start, Rect? end)? onSelectionGeometry;
  final bool spotlight;

  /// Part of the spotlight line drawn in the spotlight colour.
  final ({int start, int end})? focus;

  @override
  State<ReelText> createState() => _ReelTextState();
}

class _ReelTextState extends State<ReelText> {
  final List<GlobalKey> _keys = [];
  final _stackKey = GlobalKey();
  double _overscroll = 0;
  Object? _fitKey;

  /// The selection's first and last carets, in this widget's coordinates.
  Rect? _startCaret;
  Rect? _endCaret;
  bool _measureQueued = false;

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

  /// The piece and character nearest to [global] (for dragging handles,
  /// which may wander between and beyond lines).
  LyricHit? hitTestNearest(Offset global) {
    LyricHit? best;
    var bestDistance = double.infinity;
    for (var i = 0; i < _keys.length && i < widget.pieces.length; i++) {
      final ro = _keys[i].currentContext?.findRenderObject();
      if (ro is! RenderParagraph || !ro.attached || !ro.hasSize) continue;
      final local = ro.globalToLocal(global);
      final h = ro.size.height;
      final distance = local.dy < 0 ? -local.dy : (local.dy > h ? local.dy - h : 0.0);
      if (distance < bestDistance) {
        bestDistance = distance;
        final inside = Offset(local.dx.clamp(0.0, ro.size.width), local.dy.clamp(0.0, h - 1));
        best = LyricHit(widget.pieces[i], ro.getPositionForOffset(inside).offset);
      }
    }
    return best;
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

  List<LineMark> _marksFor(int i) => i < widget.marks.length ? widget.marks[i] : const [];

  /// A new highlight fades in; others show at full strength.
  Color _markColor(LineMark m) {
    final flash = widget.flash;
    if (!m.editing || flash == null || flash.status != AnimationStatus.forward) return m.color;
    return m.color.withValues(alpha: m.color.a * Curves.easeOut.transform(flash.value));
  }

  /// Splits [text] at highlight edges (and [extra] cuts) and styles each run.
  List<InlineSpan> _runs(String text, List<LineMark> marks, List<int> extra, TextStyle? Function(int from, int to) styleFor) {
    final cuts = <int>{0, text.length, for (final m in marks) ...[m.from, m.to], ...extra}.map((c) => c.clamp(0, text.length)).toSet().toList()
      ..sort();
    final out = <InlineSpan>[];
    for (var k = 0; k + 1 < cuts.length; k++) {
      final a = cuts[k], b = cuts[k + 1];
      if (b <= a) continue;
      Color? bg;
      for (final m in marks) {
        if (m.from <= a && m.to >= b) bg = _markColor(m);
      }
      final style = styleFor(a, b);
      out.add(TextSpan(
        text: text.substring(a, b),
        style: bg == null ? style : (style ?? const TextStyle()).copyWith(backgroundColor: bg),
      ));
    }
    return out;
  }

  InlineSpan _span(int i, LyricPiece p, TextStyle style) {
    final text = p.text;
    final marks = _marksFor(i);
    final hard = <(int, int)>[
      if (widget.hardWords.isNotEmpty)
        for (final m in RegExp(r"[A-Za-z][A-Za-z'’\-]*").allMatches(text))
          if (widget.hardWords.contains(m.group(0)!.toLowerCase())) (m.start, m.end),
    ];
    if (marks.isEmpty && hard.isEmpty) return TextSpan(text: text, style: style);
    final underline = TextStyle(
      decoration: TextDecoration.underline,
      decorationStyle: TextDecorationStyle.dotted,
      decorationColor: widget.theme.hardWordUnderline,
      decorationThickness: 2,
    );
    return TextSpan(
      style: style,
      children: _runs(text, marks, [for (final h in hard) ...[h.$1, h.$2]],
          (a, b) => hard.any((h) => h.$1 <= a && h.$2 >= b) ? underline : null),
    );
  }

  InlineSpan _spotSpan(double size) {
    final p = widget.pieces.first;
    final text = p.text;
    final f = widget.focus ?? (start: 0, end: text.length);
    final focus = widget.type.display(color: widget.theme.spot, size: size, shadows: widget.theme.textShadows);
    final rest = focus.copyWith(color: widget.theme.text.withValues(alpha: 0.84));
    return TextSpan(children: _runs(text, _marksFor(0), [f.start, f.end], (a, b) => a >= f.start && b <= f.end ? focus : rest));
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
      final text = Semantics(
        label: fullText,
        child: ExcludeSemantics(child: _overflows ? _scrollable(column) : Center(child: column)),
      );
      final selection = widget.selection;
      if (selection == null) {
        if (_startCaret != null || _endCaret != null) _queueMeasure();
        return Stack(key: _stackKey, children: [Positioned.fill(child: text)]);
      }
      _queueMeasure();
      return Stack(key: _stackKey, clipBehavior: Clip.none, children: [
        Positioned.fill(child: text),
        if (_startCaret != null) _handle(true, _startCaret!),
        if (_endCaret != null) _handle(false, _endCaret!),
      ]);
    });
  }

  /// Measures where the selection's carets are after this frame's layout.
  void _queueMeasure() {
    if (_measureQueued) return;
    _measureQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureQueued = false;
      if (!mounted) return;
      final (start, end) = _carets();
      if (start != _startCaret || end != _endCaret) {
        setState(() {
          _startCaret = start;
          _endCaret = end;
        });
      }
      final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
      Rect? global(Rect? r) => r == null || stack == null ? null : r.shift(stack.localToGlobal(Offset.zero));
      widget.onSelectionGeometry?.call(global(start), global(end));
    });
  }

  (Rect?, Rect?) _carets() {
    final selection = widget.selection;
    final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (selection == null || stack == null || !stack.hasSize) return (null, null);
    Rect? caret(int line, int offset, {required bool end}) {
      if (line < 0 || line >= _keys.length) return null;
      final ro = _keys[line].currentContext?.findRenderObject();
      if (ro is! RenderParagraph || !ro.attached || !ro.hasSize) return null;
      final length = ro.text.toPlainText().length;
      final position = TextPosition(offset: offset.clamp(0, length), affinity: end ? TextAffinity.upstream : TextAffinity.downstream);
      final topLeft = stack.globalToLocal(ro.localToGlobal(ro.getOffsetForCaret(position, Rect.zero)));
      return Rect.fromLTWH(topLeft.dx, topLeft.dy, 2, ro.getFullHeightForCaret(position));
    }

    return (
      caret(selection.startLine, selection.startOffset, end: false),
      caret(selection.endLine, selection.endOffset, end: true),
    );
  }

  /// A draggable selection handle: a caret bar with a round knob (above the
  /// first character, below the last), with a generous touch area.
  Widget _handle(bool start, Rect caret) {
    const reach = 22.0;
    return Positioned(
      left: caret.left - reach,
      top: caret.top - (start ? reach : 0),
      width: reach * 2,
      height: caret.height + reach,
      child: Semantics(
        container: true,
        label: start ? 'Start of highlight' : 'End of highlight',
        child: RawGestureDetector(
          behavior: HitTestBehavior.translucent,
          gestures: {
            ImmediateMultiDragGestureRecognizer: GestureRecognizerFactoryWithHandlers<ImmediateMultiDragGestureRecognizer>(
              ImmediateMultiDragGestureRecognizer.new,
              (r) => r.onStart = (pointer) => _beginDrag(start, pointer, caret),
            ),
          },
          child: CustomPaint(painter: _HandlePainter(color: widget.theme.accent, start: start, caretHeight: caret.height)),
        ),
      ),
    );
  }

  Drag _beginDrag(bool start, Offset pointer, Rect caret) {
    final stack = _stackKey.currentContext!.findRenderObject()! as RenderBox;
    // Keep the caret where it was relative to the finger, not under it.
    final grab = stack.localToGlobal(Offset(caret.left, caret.center.dy)) - pointer;
    HapticFeedback.selectionClick();
    return _HandleDrag(
      onUpdate: (global) => widget.onHandleDrag?.call(start, global + grab),
      onEnd: () => widget.onHandleDragEnd?.call(),
    );
  }

  /// Rebuilds [build] while a just-added highlight fades in.
  Widget _flashing(bool on, Widget Function() build) {
    final flash = widget.flash;
    if (!on || flash == null) return build();
    return AnimatedBuilder(animation: flash, builder: (context, _) => build());
  }

  Widget _lines(TextScaler scaler) {
    final n = widget.pieces.length;
    final stagger = n <= 1 ? 0.0 : (0.5 / (n - 1)).clamp(0.0, 0.1);
    final lines = <Widget>[];
    for (var i = 0; i < n; i++) {
      final p = widget.pieces[i];
      final style = _style(p, _fit);
      final start = (i * stagger).clamp(0.0, 0.5);
      final eased = CurvedAnimation(parent: widget.reveal, curve: Interval(start, start + 0.5, curve: Curves.easeOutCubic));
      if (i > 0) lines.add(SizedBox(height: _gap(p, style.fontSize!)));
      lines.add(FadeTransition(
        opacity: eased,
        child: AnimatedBuilder(
          animation: eased,
          builder: (context, child) => Transform.translate(offset: Offset(0, (1 - eased.value) * 12), child: child),
          child: SizedBox(
            width: double.infinity,
            child: _flashing(_marksFor(i).any((m) => m.editing),
                () => Text.rich(_span(i, p, style), key: _keys[i], textAlign: _textAlign(i), textScaler: scaler)),
          ),
        ),
      ));
    }
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: lines);
  }

  Widget _spotlight(TextScaler scaler) {
    final e = CurvedAnimation(parent: widget.reveal, curve: Curves.easeOutCubic);
    final bar = CurvedAnimation(parent: widget.reveal, curve: const Interval(0.3, 1, curve: Curves.easeOutCubic));
    return Column(mainAxisSize: MainAxisSize.min, children: [
      AnimatedBuilder(
        animation: bar,
        builder: (context, _) => Container(
          width: 34 * bar.value,
          height: 3,
          decoration: BoxDecoration(color: widget.theme.accent, borderRadius: BorderRadius.circular(2)),
        ),
      ),
      SizedBox(height: _fit * 0.75),
      FadeTransition(
        opacity: e,
        child: ScaleTransition(
          scale: Tween(begin: 0.95, end: 1.0).animate(e),
          child: SizedBox(
            width: double.infinity,
            child: _flashing(_marksFor(0).any((m) => m.editing),
                () => Text.rich(_spotSpan(_fit), key: _keys[0], textAlign: TextAlign.center, textScaler: scaler)),
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
    final cover = coverPath != null && fileExists(coverPath!) ? FileImage(File(coverPath!)) : null;
    final initials = title.trim().isEmpty ? '📖' : title.trim()[0].toUpperCase();
    final shadow = shadows;
    return Row(children: [
      Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [accent, accent.withValues(alpha: 0.4)])),
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF2F3A35),
            image: cover == null ? null : DecorationImage(image: ResizeImage(cover, width: 108), fit: BoxFit.cover),
          ),
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
    Widget b(IconData icon, String label, String semantic, VoidCallback onTap, {Color? color, bool active = false}) => _RailButton(
          icon: Icon(icon, color: color ?? ink, size: 31, shadows: shadows),
          label: label,
          semanticLabel: semantic,
          color: color ?? ink,
          shadows: shadows,
          active: active,
          onTap: onTap,
        );
    return Column(mainAxisSize: MainAxisSize.min, children: [
      b(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded, liked ? 'Liked' : 'Like', liked ? 'Unlike' : 'Like', onLike,
          color: liked ? ember : null, active: liked),
      b(saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, saved ? 'Saved' : 'Save', saved ? 'Saved' : 'Save', onSave,
          color: saved ? accent : null, active: saved),
      b(Icons.edit_note_rounded, 'Note', 'Highlight & note', onNote),
      // The reels-style share arrow (curving up and to the right).
      _RailButton(
        icon: ShareArrowIcon(size: 33, color: ink, shadows: shadows),
        label: 'Share',
        semanticLabel: 'Share',
        color: ink,
        shadows: shadows,
        onTap: onShare,
      ),
      b(listening ? Icons.stop_circle_outlined : Icons.headphones_rounded, listening ? 'Stop' : 'Listen',
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
    required this.semanticLabel,
    required this.color,
    required this.shadows,
    required this.onTap,
    this.active = false,
  });

  final Widget icon;
  final String label;
  final String semanticLabel;
  final Color color;
  final List<Shadow>? shadows;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final shadow = shadows;
    return KitPressable(
      onTap: onTap,
      semanticLabel: semanticLabel,
      excludeSemantics: true,
      pressedScale: 0.86,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TweenAnimationBuilder<double>(
            key: ValueKey(active),
            tween: Tween(begin: active ? 0.55 : 1, end: 1),
            duration: const Duration(milliseconds: 420),
            curve: Curves.elasticOut,
            builder: (context, v, child) => Transform.scale(scale: v, child: child),
            child: icon,
          ),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w700, shadows: shadow)),
        ]),
      ),
    );
  }
}

class _SwipeHint extends StatelessWidget {
  const _SwipeHint({required this.icon, required this.label, required this.color, required this.armed});
  final Widget icon;
  final String label;
  final Color color;
  final bool armed;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: armed ? 1.15 : 1,
      duration: const Duration(milliseconds: 150),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, color: armed ? color : const Color(0x66000000)),
          child: icon,
        ),
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
    return AnimatedBuilder(animation: burst.controller, builder: (context, _) => _frame());
  }

  Widget _frame() {
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
