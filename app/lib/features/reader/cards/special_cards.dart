import 'package:flutter/material.dart';

import '../../../core/models/reel_card.dart';
import '../../../data/settings.dart';
import '../../../ui/theme.dart';
import '../../../ui/typography.dart';

/// Text in the book's own body font (the quiz, recap and reflect cards
/// belong to the book too).
TextStyle _serif(BookType type, ReadingTheme t, {double scale = 1, FontWeight? weight, Color? color}) =>
    type.body(color: color ?? t.text, scale: scale).copyWith(fontWeight: weight, height: 1.3);

class _CardFrame extends StatelessWidget {
  const _CardFrame({required this.child, required this.theme, this.bare = false});
  final Widget child;
  final ReadingTheme theme;

  /// Full-screen content straight on the scene (no panel), with a shade.
  final bool bare;

  @override
  Widget build(BuildContext context) {
    final onScene = theme.onScene;
    if (bare) {
      // The reader draws the scene's calibrated shade behind every reel.
      final padding = MediaQuery.paddingOf(context);
      return Padding(
        padding: EdgeInsets.fromLTRB(32, padding.top + 96, 32, padding.bottom + 48),
        child: Center(child: SingleChildScrollView(child: child)),
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(14, MediaQuery.paddingOf(context).top + 96, 14, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: onScene ? theme.glass : theme.background,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: !onScene
                    ? theme.muted.withValues(alpha: 0.18)
                    : theme.isDark
                        ? const Color(0x24FFFFFF)
                        : const Color(0x1A000000),
              ),
              boxShadow: onScene ? const [BoxShadow(color: Color(0x33000000), blurRadius: 30, offset: Offset(0, 12))] : null,
            ),
            child: SingleChildScrollView(child: child),
          ),
        ),
      ),
    );
  }
}

/// Full-bleed chapter card: a breathing point between chapters.
class ChapterTitleCardView extends StatelessWidget {
  const ChapterTitleCardView({
    super.key,
    required this.title,
    required this.chapterNumber,
    required this.cards,
    required this.minutes,
    required this.settings,
    required this.theme,
    required this.type,
    this.teaser,
  });

  final String title;
  final int chapterNumber;
  final int cards;
  final int minutes;
  final String? teaser;
  final AppSettings settings;
  final ReadingTheme theme;
  final BookType type;

  @override
  Widget build(BuildContext context) {
    final shadows = theme.textShadows;
    final accent = theme.accent;
    // "CHAPTER I. Down the Rabbit-Hole" → "Down the Rabbit-Hole" (the label above says Chapter 1).
    final stripped = title.replaceFirst(RegExp(r'^\s*chapter\s+[0-9ivxlcdm]+\s*[.:\-–—]?\s*', caseSensitive: false), '');
    final heading = stripped.isEmpty ? title : stripped;
    return _CardFrame(
      theme: theme,
      bare: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('CHAPTER $chapterNumber',
              style: TextStyle(color: accent, fontWeight: FontWeight.w800, letterSpacing: 3, fontSize: 15, shadows: shadows)),
          const SizedBox(height: 14),
          Semantics(
            header: true,
            child: Text(heading,
                style: type.display(color: theme.spot, size: (settings.fontSize * 1.9).clamp(30.0, 52.0), shadows: shadows)),
          ),
          const SizedBox(height: 20),
          Text('$cards cards · ~$minutes min', style: TextStyle(color: theme.muted, fontSize: 15, fontWeight: FontWeight.w600, shadows: shadows)),
          if (teaser != null) ...[
            const SizedBox(height: 24),
            Text(teaser!, style: type.body(color: theme.text, scale: 1.02, shadows: shadows)),
          ],
          const SizedBox(height: 40),
          Row(children: [
            Icon(Icons.keyboard_arrow_up, color: theme.muted),
            const SizedBox(width: 4),
            Text('Swipe up to begin', style: TextStyle(color: theme.muted)),
          ]),
        ],
      ),
    );
  }
}

class _AiChip extends StatelessWidget {
  const _AiChip({required this.label, required this.theme});
  final String label;
  final ReadingTheme theme;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(border: Border.all(color: theme.muted), borderRadius: BorderRadius.circular(20)),
        child: Text(label, style: TextStyle(color: theme.muted, fontSize: 12, fontWeight: FontWeight.w600)),
      );
}

/// AI recap, clearly marked so it is never confused with the author's text.
class RecapCardView extends StatelessWidget {
  const RecapCardView({super.key, required this.bullets, required this.settings, required this.theme, required this.type});
  final List<String> bullets;
  final AppSettings settings;
  final ReadingTheme theme;
  final BookType type;

  @override
  Widget build(BuildContext context) {
    return _CardFrame(
      theme: theme,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        _AiChip(label: 'AI SUMMARY', theme: theme),
        const SizedBox(height: 16),
        Text('So far', style: _serif(type, theme, scale: 1.3, weight: FontWeight.w600)),
        const SizedBox(height: 16),
        for (final b in bullets)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('•  ', style: _serif(type, theme)),
              Expanded(child: Text(b, style: _serif(type, theme, scale: 0.95))),
            ]),
          ),
      ]),
    );
  }
}

/// Optional retrieval practice (testing effect). No penalty for wrong answers.
class RecallCardView extends StatefulWidget {
  const RecallCardView({
    super.key,
    required this.settings,
    required this.theme,
    required this.type,
    this.question,
    this.revealSentences = const [],
    required this.onAnswered,
  });

  final AppSettings settings;
  final ReadingTheme theme;
  final BookType type;
  final RecallQuestion? question;
  final List<String> revealSentences;
  final void Function(bool correct) onAnswered;

  @override
  State<RecallCardView> createState() => _RecallCardViewState();
}

class _RecallCardViewState extends State<RecallCardView> {
  int? _picked;
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.type;
    final t = widget.theme;
    final q = widget.question;
    return _CardFrame(
      theme: t,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        _AiChip(label: q == null ? 'QUICK CHECK' : 'AI QUICK CHECK', theme: t),
        const SizedBox(height: 16),
        Text(q?.question ?? 'Pause and recall: what was the main idea of the last few cards?',
            style: _serif(s, t, scale: 1.15, weight: FontWeight.w600)),
        const SizedBox(height: 20),
        if (q != null)
          for (var i = 0; i < q.options.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _OptionTile(
                text: q.options[i],
                theme: t,
                state: _picked == null
                    ? _OptionState.idle
                    : i == q.answerIndex
                        ? _OptionState.correct
                        : i == _picked
                            ? _OptionState.wrong
                            : _OptionState.idle,
                onTap: _picked != null
                    ? null
                    : () {
                        setState(() => _picked = i);
                        widget.onAnswered(i == q.answerIndex);
                      },
              ),
            )
        else if (!_revealed)
          FilledButton.tonal(
            onPressed: () {
              setState(() => _revealed = true);
              widget.onAnswered(true);
            },
            child: const Text('Tap to reveal'),
          )
        else ...[
          Text('Key points', style: TextStyle(color: t.muted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          for (final r in widget.revealSentences)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text('“$r”', style: _serif(s, t, scale: 0.95)),
            ),
        ],
        if (_picked != null && q != null) ...[
          const SizedBox(height: 8),
          Text(_picked == q.answerIndex ? 'Nice, that stuck. ✨' : 'Close. The highlighted one is it.',
              style: TextStyle(color: t.muted)),
        ],
        const SizedBox(height: 24),
        Text('Swipe up to continue', style: TextStyle(color: t.muted, fontSize: 13)),
      ]),
    );
  }
}

enum _OptionState { idle, correct, wrong }

class _OptionTile extends StatelessWidget {
  const _OptionTile({required this.text, required this.theme, required this.state, this.onTap});
  final String text;
  final ReadingTheme theme;
  final _OptionState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      _OptionState.correct => const Color(0x5567C587),
      _OptionState.wrong => theme.muted.withValues(alpha: 0.18),
      _OptionState.idle => Colors.transparent,
    };
    return Material(
      color: color,
      shape: RoundedRectangleBorder(side: BorderSide(color: theme.muted.withValues(alpha: 0.5)), borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              Expanded(child: Text(text, style: TextStyle(color: theme.text, fontSize: 16))),
              if (state == _OptionState.correct) Icon(Icons.check_circle, color: theme.text),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Chapter-end reflection (generation + self-reference effects). Skip is as
/// prominent as Save.
class ReflectCardView extends StatefulWidget {
  const ReflectCardView({super.key, required this.settings, required this.theme, required this.type, required this.onSave});
  final AppSettings settings;
  final ReadingTheme theme;
  final BookType type;
  final void Function(String text) onSave;

  @override
  State<ReflectCardView> createState() => _ReflectCardViewState();
}

class _ReflectCardViewState extends State<ReflectCardView> {
  final _controller = TextEditingController();
  bool _saved = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    return _CardFrame(
      theme: t,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        _AiChip(label: 'REFLECT', theme: t),
        const SizedBox(height: 16),
        Text('One idea from this chapter you’ll carry with you?',
            style: _serif(widget.type, t, scale: 1.15, weight: FontWeight.w600)),
        const SizedBox(height: 20),
        if (_saved)
          Row(children: [
            Icon(Icons.check, color: t.text),
            const SizedBox(width: 8),
            Text('Saved to your Notebook', style: TextStyle(color: t.text)),
          ])
        else ...[
          TextField(
            controller: _controller,
            minLines: 2,
            maxLines: 5,
            style: TextStyle(color: t.text),
            decoration: InputDecoration(
              hintText: 'Write a sentence…',
              hintStyle: TextStyle(color: t.muted),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            FilledButton(
              onPressed: () {
                if (_controller.text.trim().isEmpty) return;
                widget.onSave(_controller.text);
                FocusScope.of(context).unfocus();
                setState(() => _saved = true);
              },
              child: const Text('Save'),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: () => FocusScope.of(context).unfocus(),
              child: Text('Skip', style: TextStyle(color: t.text)),
            ),
          ]),
        ],
        const SizedBox(height: 24),
        Text('Swipe up to continue', style: TextStyle(color: t.muted, fontSize: 13)),
      ]),
    );
  }
}

class MilestoneCardView extends StatelessWidget {
  const MilestoneCardView({
    super.key,
    required this.bookTitle,
    required this.settings,
    required this.theme,
    required this.type,
    required this.onShare,
    required this.onDone,
  });

  final String bookTitle;
  final AppSettings settings;
  final ReadingTheme theme;
  final BookType type;
  final VoidCallback onShare;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return _CardFrame(
      theme: theme,
      bare: true,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('🎉', style: TextStyle(fontSize: 64)),
        const SizedBox(height: 16),
        Text('You finished', style: _serif(type, theme, scale: 0.9, color: theme.muted)),
        const SizedBox(height: 8),
        Text(bookTitle,
            textAlign: TextAlign.center,
            style: type.display(color: theme.spot, size: (settings.fontSize * 1.8).clamp(28.0, 48.0), shadows: theme.textShadows)),
        const SizedBox(height: 32),
        FilledButton.icon(onPressed: onShare, icon: const Icon(Icons.ios_share), label: const Text('Share')),
        const SizedBox(height: 8),
        TextButton(onPressed: onDone, child: Text('Back to library', style: TextStyle(color: theme.text))),
      ]),
    );
  }
}
