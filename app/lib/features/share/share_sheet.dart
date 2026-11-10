import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/share/quote_limit.dart';
import '../../data/api_client.dart';

enum ShareTemplate { paper, dark, ember, minimal, ocean }

enum ShareAspect {
  story(9 / 16, '9:16'),
  portrait(4 / 5, '4:5'),
  square(1, '1:1');

  const ShareAspect(this.ratio, this.label);
  final double ratio;
  final String label;
}

/// What is being shared: a quote from a card, or a progress stat.
sealed class ShareContent {
  const ShareContent();
}

class QuoteShare extends ShareContent {
  const QuoteShare({
    required this.sentences,
    required this.bookTitle,
    required this.author,
    required this.publicDomain,
    this.chapter,
  });
  final List<String> sentences;
  final String bookTitle;
  final String author;
  final bool publicDomain;
  final String? chapter;
}

class ProgressShare extends ShareContent {
  const ProgressShare({required this.headline, required this.lines, this.emoji = '📚'});
  final String headline;
  final List<String> lines;
  final String emoji;
}

/// One-tap share sheet with a live preview (UX_DESIGN.md §5.6): the preview is
/// rendered locally the moment the sheet opens; one more tap shares it.
Future<void> showShareSheet(BuildContext context, ShareContent content) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ShareSheet(content: content),
  );
}

class _ShareSheet extends ConsumerStatefulWidget {
  const _ShareSheet({required this.content});
  final ShareContent content;

  @override
  ConsumerState<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends ConsumerState<_ShareSheet> {
  final _boundaryKey = GlobalKey();
  ShareTemplate _template = ShareTemplate.paper;
  ShareAspect _aspect = ShareAspect.story;
  bool _busy = false;

  String get _plainText {
    final c = widget.content;
    return switch (c) {
      QuoteShare() =>
        '“${limitQuote(c.sentences, publicDomain: c.publicDomain).text}”\n— ${c.author}, ${c.bookTitle}\n\nRead it on BookReel',
      ProgressShare() => '${c.emoji} ${c.headline}\n${c.lines.join('\n')}\n\nReading on BookReel',
    };
  }

  /// A short link to a web preview, when the server is available. Sharing
  /// never waits more than a few seconds for it.
  Future<String?> _link() async {
    final api = ref.read(apiProvider);
    if (!api.enabled) return null;
    final c = widget.content;
    final payload = switch (c) {
      QuoteShare() => {
          'type': 'quote',
          'text': limitQuote(c.sentences, publicDomain: c.publicDomain).text,
          'book_title': c.bookTitle,
          'author': c.author,
          'public_domain': c.publicDomain,
        },
      ProgressShare() => {'type': 'progress', 'headline': c.headline, 'lines': c.lines},
    };
    try {
      return await api.createShare(payload).timeout(const Duration(seconds: 4));
    } catch (_) {
      return null;
    }
  }

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      final link = await _link();
      final boundary = _boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/bookreel_share_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      final text = link == null ? _plainText : '$_plainText\n$link';
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'image/png')], text: text));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not share: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final height = MediaQuery.sizeOf(context).height;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            height: height * 0.45,
            child: FittedBox(
              child: RepaintBoundary(
                key: _boundaryKey,
                child: ShareCardArt(content: widget.content, template: _template, aspect: _aspect),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 44,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final t in ShareTemplate.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(t.name[0].toUpperCase() + t.name.substring(1)),
                    selected: t == _template,
                    onSelected: (_) => setState(() => _template = t),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 8),
          SegmentedButton<ShareAspect>(
            segments: [for (final a in ShareAspect.values) ButtonSegment(value: a, label: Text(a.label))],
            selected: {_aspect},
            onSelectionChanged: (s) => setState(() => _aspect = s.first),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: _plainText));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
                  }
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copy text'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy ? null : _share,
                icon: _busy
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.onPrimary))
                    : const Icon(Icons.ios_share),
                label: const Text('Share'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// The shareable image, laid out at 360 logical px wide (1080 px at 3×).
class ShareCardArt extends StatelessWidget {
  const ShareCardArt({super.key, required this.content, required this.template, required this.aspect});

  final ShareContent content;
  final ShareTemplate template;
  final ShareAspect aspect;

  static const width = 360.0;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, muted, gradient) = switch (template) {
      ShareTemplate.paper => (const Color(0xFFFBF8F1), const Color(0xFF1F1D1A), const Color(0xFF7A746A), null),
      ShareTemplate.dark => (const Color(0xFF141414), const Color(0xFFE6E1D6), const Color(0xFF9A948A), null),
      ShareTemplate.minimal => (Colors.white, Colors.black, const Color(0xFF777777), null),
      ShareTemplate.ember => (
          const Color(0xFFD9822B),
          Colors.white,
          Colors.white70,
          const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFE6A04A), Color(0xFFB4532A)]),
        ),
      ShareTemplate.ocean => (
          const Color(0xFF2F5D62),
          Colors.white,
          Colors.white70,
          const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF3D7C83), Color(0xFF1E3B4D)]),
        ),
    };
    final height = width / aspect.ratio;
    final c = content;
    final Widget body = switch (c) {
      QuoteShare() => _quoteBody(c, fg, muted),
      ProgressShare() => _progressBody(c, fg, muted),
    };
    return MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.noScaling),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(color: bg, gradient: gradient),
        padding: const EdgeInsets.fromLTRB(32, 40, 32, 28),
        child: DefaultTextStyle(
          style: TextStyle(color: fg, fontFamily: 'Literata', decoration: TextDecoration.none),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Center(child: body)),
            Row(children: [
              Icon(Icons.auto_stories, size: 16, color: muted),
              const SizedBox(width: 6),
              Text('BookReel', style: TextStyle(fontFamily: null, fontWeight: FontWeight.w700, fontSize: 13, color: muted)),
              const Spacer(),
              Text('bookreel.app', style: TextStyle(fontFamily: null, fontSize: 12, color: muted)),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _quoteBody(QuoteShare q, Color fg, Color muted) {
    final excerpt = limitQuote(q.sentences, publicDomain: q.publicDomain).text;
    final long = excerpt.length > 420;
    final size = aspect == ShareAspect.square ? (long ? 13.0 : 17.0) : (long ? 15.0 : 20.0);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text('“', style: TextStyle(fontSize: 56, height: 0.8, color: muted)),
      Flexible(
        child: Text(excerpt,
            overflow: TextOverflow.fade,
            style: TextStyle(fontSize: size, height: 1.45, color: fg)),
      ),
      const SizedBox(height: 18),
      Text('— ${q.author}', style: TextStyle(fontSize: 14, color: fg, fontWeight: FontWeight.w600)),
      Text(q.bookTitle, style: TextStyle(fontSize: 13, color: muted, fontStyle: FontStyle.italic)),
    ]);
  }

  Widget _progressBody(ProgressShare p, Color fg, Color muted) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(p.emoji, style: const TextStyle(fontSize: 56)),
      const SizedBox(height: 16),
      Text(p.headline, textAlign: TextAlign.center, style: TextStyle(fontSize: 24, height: 1.25, color: fg, fontWeight: FontWeight.w600)),
      const SizedBox(height: 16),
      for (final l in p.lines)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(l, textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: muted, fontFamily: null)),
        ),
    ]);
  }
}
