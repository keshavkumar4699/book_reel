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
import '../../ui/kit.dart';
import '../../l10n/l10n.dart';

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

/// Reading progress to share, Strava-style: a headline, what it was about,
/// and the figures (cards, words, time, streak…) in a grid.
class ProgressShare extends ShareContent {
  const ProgressShare({required this.headline, this.lines = const [], this.emoji = '📚', this.subtitle, this.stats = const []});
  final String headline;

  /// The book, or who's sharing.
  final String? subtitle;
  final List<String> lines;
  final String emoji;

  /// Figures as (value, label), e.g. ('3.1k', 'words').
  final List<(String, String)> stats;

  /// The figures in one line: "24 cards · 3.1k words · 18 min" (a time
  /// carries its own unit).
  String get statsLine => [for (final (v, l) in stats) l == tr('time') ? v : '$v $l'].join(' · ');
}

/// Minutes as "18 min", "1 h 5 min" or "3 h".
String shareDuration(double minutes) {
  final m = minutes.round();
  if (m < 60) return tr('{n} min', {'n': m});
  return m % 60 == 0 ? tr('{h} h', {'h': m ~/ 60}) : tr('{h} h {m} min', {'h': m ~/ 60, 'm': m % 60});
}

/// One-tap share sheet with a live preview (UX_DESIGN.md §5.6): the preview is
/// rendered locally the moment the sheet opens; one more tap shares it.
Future<void> showShareSheet(BuildContext context, ShareContent content) {
  return showKitSheet<void>(
    context,
    title: tr('Share'),
    maxHeight: 0.94,
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
        '“${limitQuote(c.sentences, publicDomain: c.publicDomain).text}”\n— ${c.author}, ${c.bookTitle}\n\n${tr('Read it on Cloro')}',
      ProgressShare() => [
          '${c.emoji} ${c.headline}',
          ?c.subtitle,
          if (c.stats.isNotEmpty) c.statsLine,
          ...c.lines,
          '',
          tr('Reading on Cloro'),
        ].join('\n'),
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
      ProgressShare() => {
          'type': 'progress',
          'headline': c.headline,
          // The web page shows up to 4 lines of up to 140 characters.
          'lines': [
            ?c.subtitle,
            if (c.stats.isNotEmpty) c.statsLine,
            ...c.lines,
          ].take(4).map((l) => l.length > 140 ? '${l.substring(0, 139)}…' : l).toList(),
        },
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
      if (mounted) showKitToast(context, tr('Could not share: {error}', {'error': e}), icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        height: height * 0.42,
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
              child: KitChip(
                label: t.name[0].toUpperCase() + t.name.substring(1),
                selected: t == _template,
                onTap: () => setState(() => _template = t),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 10),
      KitSegmented<ShareAspect>(
        values: ShareAspect.values,
        selected: _aspect,
        label: (a) => a.label,
        onChanged: (a) => setState(() => _aspect = a),
      ),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(
          child: KitButton.secondary(
            label: tr('Copy text'),
            icon: Icons.copy_rounded,
            expand: true,
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _plainText));
              if (context.mounted) showKitToast(context, tr('Copied'), icon: Icons.check_rounded);
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: KitButton(
            label: _busy ? tr('Preparing…') : tr('Share'),
            leading: _busy ? const SizedBox(width: 18, height: 18, child: KitSpinner(size: 18)) : const ShareArrowIcon(),
            expand: true,
            onPressed: _busy ? null : _share,
          ),
        ),
      ]),
    ]);
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
      // The logo's gradient, as artwork on a shared card.
      ShareTemplate.ember => (
          const Color(0xFFFF3131),
          Colors.white,
          Colors.white70,
          const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFF3131), Color(0xFFFF914D)]),
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
              Text('Cloro', style: TextStyle(fontFamily: null, fontWeight: FontWeight.w700, fontSize: 13, color: muted)),
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
    if (p.stats.isNotEmpty) return _statsBody(p, fg, muted);
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

  /// Strava-style: the headline and what it was about at the top, then the
  /// figures in a grid, each a big value over a small label.
  Widget _statsBody(ProgressShare p, Color fg, Color muted) {
    final square = aspect == ShareAspect.square;
    final columns = p.stats.length <= 4 ? 2 : 3;
    final valueSize = square ? 24.0 : (columns == 2 ? 34.0 : 28.0);
    // The app's own sans faces for figures, as on a run's summary.
    Widget figure((String, String) f) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(f.$2.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 11,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w800,
                  fontVariations: const [FontVariation('wght', 800)],
                  color: muted)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(f.$1,
                maxLines: 1,
                style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: valueSize,
                    height: 1.1,
                    fontWeight: FontWeight.w700,
                    fontVariations: const [FontVariation('wght', 700)],
                    color: fg)),
          ),
        ]);
    final rows = <Widget>[];
    for (var i = 0; i < p.stats.length; i += columns) {
      rows.add(Padding(
        padding: EdgeInsets.only(bottom: square ? 12 : 20),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var j = i; j < i + columns; j++) Expanded(child: j < p.stats.length ? figure(p.stats[j]) : const SizedBox()),
        ]),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(p.emoji, style: TextStyle(fontSize: square ? 36 : 48)),
      SizedBox(height: square ? 8 : 14),
      Text(p.headline, style: TextStyle(fontSize: square ? 21 : 26, height: 1.2, color: fg, fontWeight: FontWeight.w600)),
      if (p.subtitle != null) ...[
        const SizedBox(height: 6),
        Text(p.subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, color: muted, fontStyle: FontStyle.italic)),
      ],
      SizedBox(height: square ? 18 : 30),
      ...rows,
      for (final l in p.lines)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(l, style: TextStyle(fontSize: 13.5, color: muted, fontFamily: null)),
        ),
    ]);
  }
}
