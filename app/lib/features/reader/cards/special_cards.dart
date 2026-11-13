import 'package:flutter/material.dart';

import '../../../core/models/reel_card.dart';
import '../../../data/settings.dart';
import '../../../ui/kit.dart';
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
    if (bare) {
      // The reader draws the scene's calibrated shade behind every reel.
      final padding = MediaQuery.paddingOf(context);
      return Padding(
        padding: EdgeInsets.fromLTRB(32, padding.top + 96, 32, padding.bottom + 48),
        child: Center(child: SingleChildScrollView(child: child)),
      );
    }
    // No panel: the text sits straight on the page or on the scene's
    // calibrated shade (which the reader draws behind every reel).
    return Padding(
      padding: EdgeInsets.fromLTRB(32, MediaQuery.paddingOf(context).top + 96, 32, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: SizedBox(width: double.infinity, child: SingleChildScrollView(child: child)),
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
  Widget build(BuildContext context) =>
      Text(label, style: TextStyle(color: theme.muted, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8));
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
          KitButton.secondary(
            label: 'Tap to reveal',
            onPressed: () {
              setState(() => _revealed = true);
              widget.onAnswered(true);
            },
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
    // A plain row (no box): an empty circle, then a tick or a cross once answered.
    final icon = switch (state) {
      _OptionState.correct => Icons.check_circle_rounded,
      _OptionState.wrong => Icons.cancel_outlined,
      _OptionState.idle => Icons.radio_button_unchecked_rounded,
    };
    return KitPressable(
      onTap: onTap,
      pressedScale: 0.98,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            Icon(icon, color: state == _OptionState.wrong ? theme.muted : theme.text),
            const SizedBox(width: 14),
            Expanded(
              child: Text(text,
                  style: TextStyle(
                      color: state == _OptionState.wrong ? theme.muted : theme.text,
                      fontSize: 16,
                      fontWeight: state == _OptionState.correct ? FontWeight.w700 : FontWeight.w400)),
            ),
          ]),
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
          KitTextField(controller: _controller, hint: 'Write a sentence…', minLines: 2, maxLines: 5),
          const SizedBox(height: 12),
          Row(children: [
            KitButton(
              label: 'Save',
              compact: true,
              onPressed: () {
                if (_controller.text.trim().isEmpty) return;
                widget.onSave(_controller.text);
                FocusScope.of(context).unfocus();
                setState(() => _saved = true);
              },
            ),
            const SizedBox(width: 10),
            KitButton.secondary(label: 'Skip', compact: true, onPressed: () => FocusScope.of(context).unfocus()),
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
        KitButton(label: 'Share', leading: const ShareArrowIcon(), onPressed: onShare),
        const SizedBox(height: 8),
        KitButton.ghost(label: 'Back to library', onPressed: onDone),
      ]),
    );
  }
}
