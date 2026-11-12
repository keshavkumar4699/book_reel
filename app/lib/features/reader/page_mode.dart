import 'package:flutter/material.dart';

import '../../core/models/book.dart';
import '../../core/parsing/block_builder.dart';
import '../../data/settings.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';

/// Classic continuous reading of one chapter (DESIGN.md §2.3). Shares the
/// sentence-ID position model with the reel feed. Returns the sentence ID to
/// resume from when closed.
class PageModeView extends StatefulWidget {
  const PageModeView({
    super.key,
    required this.book,
    required this.chapterIndex,
    required this.anchorSid,
    required this.settings,
    required this.theme,
  });

  final BookContent book;
  final int chapterIndex;
  final String? anchorSid;
  final AppSettings settings;
  final ReadingTheme theme;

  @override
  State<PageModeView> createState() => _PageModeViewState();
}

class _PageModeViewState extends State<PageModeView> {
  late int _chapter = widget.chapterIndex;
  final _anchorKey = GlobalKey();
  final _scroll = ScrollController();
  String? _resumeSid;

  @override
  void initState() {
    super.initState();
    _resumeSid = widget.anchorSid;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _anchorKey.currentContext;
      if (ctx != null) Scrollable.ensureVisible(ctx, alignment: 0.1);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _goChapter(int index) {
    setState(() {
      _chapter = index;
      _resumeSid = widget.book.chapters[index].blocks.first.sentences.first.id;
    });
    _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final s = widget.settings;
    final chapter = widget.book.chapters[_chapter];
    final anchorBlock = _resumeSid == null ? null : parseSid(_resumeSid!);
    final base = TextStyle(
      fontFamily: fontFamilyFor(s.font),
      fontSize: s.fontSize,
      height: s.lineHeight,
      letterSpacing: s.letterSpacing,
      wordSpacing: s.wordSpacing,
      color: t.text,
    );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_resumeSid);
      },
      // Page mode is plain paper: its controls wear the paper theme.
      child: Theme(
        data: Theme.of(context).copyWith(extensions: [Kit.forScene(Vibe.paper, t)]),
        child: Builder(builder: (context) => Scaffold(
        backgroundColor: t.background,
        body: SafeArea(
          bottom: false,
          child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 16, 4),
            child: Row(children: [
              KitIconButton(
                icon: Icons.view_carousel_rounded,
                semanticLabel: 'Back to reels',
                onPressed: () => Navigator.of(context).pop(_resumeSid),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(chapter.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Kit.of(context).heading)),
            ]),
          ),
          Expanded(
          child: SingleChildScrollView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 48),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final b in chapter.blocks)
              Padding(
                key: anchorBlock != null && anchorBlock.chapter == _chapter && anchorBlock.block == b.index ? _anchorKey : null,
                padding: EdgeInsets.only(bottom: s.fontSize * 0.7),
                child: isSceneBreakBlock(b)
                    ? Center(child: Text('⁂', style: base.copyWith(color: t.muted)))
                    : GestureDetector(
                        onTap: () => _resumeSid = b.sentences.first.id,
                        child: Text(
                          b.type == BlockType.quote ? b.sentences.map((x) => x.text).join('\n') : b.text,
                          style: switch (b.type) {
                            BlockType.heading => base.copyWith(fontWeight: FontWeight.w600, fontSize: s.fontSize * 1.15),
                            BlockType.quote => base.copyWith(fontStyle: FontStyle.italic),
                            _ => base,
                          },
                        ),
                      ),
              ),
            const SizedBox(height: 24),
            Row(children: [
              if (_chapter > 0)
                KitButton.ghost(label: 'Previous', icon: Icons.chevron_left_rounded, compact: true, onPressed: () => _goChapter(_chapter - 1)),
              const Spacer(),
              if (_chapter < widget.book.chapters.length - 1)
                KitButton(label: 'Next chapter', icon: Icons.chevron_right_rounded, compact: true, onPressed: () => _goChapter(_chapter + 1)),
            ]),
          ]),
        ),
          ),
          ]),
        ),
      )),
      ),
    );
  }
}
