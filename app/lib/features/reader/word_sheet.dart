import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/text/lexicon.dart';
import '../../data/notebook.dart';
import '../../services/tts.dart';
import '../../ui/kit.dart';

/// Word sheet (UX_DESIGN.md §5.4): meaning in this sentence first, then
/// dictionary senses, pronunciation and "add to word list". The meaning in
/// context comes from the AI cards (paid plans) or, on Free with the
/// on-device model, from [onDeviceMeaning], asked when the sheet opens.
Future<void> showWordSheet(
  BuildContext context, {
  required String word,
  required String sentence,
  required String bookTitle,
  required Lexicon lexicon,
  String? contextMeaning,
  Future<String?> Function()? onDeviceMeaning,
}) {
  final entry = lexicon.lookup(word);
  return showKitSheet<void>(
    context,
    title: entry?.lemma ?? word.toLowerCase(),
    maxHeight: 0.8,
    trailing: KitIconButton(icon: Icons.volume_up_rounded, semanticLabel: 'Pronounce', onPressed: () => Tts.instance.speak(word)),
    builder: (context) => _WordSheet(
      word: word,
      sentence: sentence,
      bookTitle: bookTitle,
      entry: entry,
      contextMeaning: contextMeaning,
      onDeviceMeaning: contextMeaning == null ? onDeviceMeaning : null,
    ),
  );
}

class _WordSheet extends ConsumerStatefulWidget {
  const _WordSheet({
    required this.word,
    required this.sentence,
    required this.bookTitle,
    required this.entry,
    this.contextMeaning,
    this.onDeviceMeaning,
  });

  final String word;
  final String sentence;
  final String bookTitle;
  final DictionaryEntry? entry;
  final String? contextMeaning;
  final Future<String?> Function()? onDeviceMeaning;

  @override
  ConsumerState<_WordSheet> createState() => _WordSheetState();
}

class _WordSheetState extends ConsumerState<_WordSheet> {
  /// The on-device model's answer: pending, then the meaning or null.
  bool _asking = false;
  String? _local;

  @override
  void initState() {
    super.initState();
    final ask = widget.onDeviceMeaning;
    if (ask != null) {
      _asking = true;
      ask().then((m) {
        if (!mounted) return;
        setState(() {
          _asking = false;
          _local = m;
        });
      }, onError: (Object _) {
        if (mounted) setState(() => _asking = false);
      });
    }
  }

  Widget _inContext(Kit kit, String text, {String label = 'IN THIS SENTENCE'}) => KitPanel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: kit.label.copyWith(color: kit.accent)),
          const SizedBox(height: 6),
          Text(text, style: kit.heading),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    final word = widget.word;
    final entry = widget.entry;
    final saved = ref.watch(notebookProvider).hasWord(word);
    final contextMeaning = widget.contextMeaning ?? _local;
    final meaning = contextMeaning ?? entry?.senses.first.definition;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (widget.contextMeaning != null)
        _inContext(kit, widget.contextMeaning!)
      else if (_local != null)
        _inContext(kit, _local!, label: 'IN THIS SENTENCE · ON-DEVICE AI')
      else if (_asking)
        KitPanel(
          child: Row(children: [
            KitSpinner(size: 18, color: kit.accent),
            const SizedBox(width: 12),
            Expanded(child: Text('Working out what it means here, on your phone…', style: kit.caption)),
          ]),
        ),
      const SizedBox(height: 14),
      if (entry == null && contextMeaning == null)
        Text(_asking ? '' : 'No offline definition for “$word”.', style: kit.body)
      else if (entry != null) ...[
        Text('DICTIONARY', style: kit.label),
        const SizedBox(height: 8),
        for (final s in entry.senses)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: '${s.partOfSpeech}  ', style: kit.caption.copyWith(fontStyle: FontStyle.italic, color: kit.accent)),
                  TextSpan(text: s.definition),
                ]),
                style: kit.body,
              ),
              if (s.example != null) Text('“${s.example}”', style: kit.caption),
            ]),
          ),
      ],
      const SizedBox(height: 6),
      KitButton(
        label: saved ? 'In your word list' : 'Add to word list',
        icon: saved ? Icons.check_rounded : Icons.add_rounded,
        kind: saved ? KitButtonKind.secondary : KitButtonKind.primary,
        expand: true,
        onPressed: saved || meaning == null
            ? null
            : () => ref.read(notebookProvider.notifier).addWord(
                  word: entry?.lemma ?? word.toLowerCase(),
                  meaning: meaning,
                  sentence: widget.sentence,
                  bookTitle: widget.bookTitle,
                ),
      ),
    ]);
  }
}
