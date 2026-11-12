import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/text/lexicon.dart';
import '../../data/notebook.dart';
import '../../services/tts.dart';
import '../../ui/kit.dart';

/// Word sheet (UX_DESIGN.md §5.4): meaning in this sentence first, then
/// dictionary senses, pronunciation and "add to word list".
Future<void> showWordSheet(
  BuildContext context, {
  required String word,
  required String sentence,
  required String bookTitle,
  required Lexicon lexicon,
  String? contextMeaning,
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
    ),
  );
}

class _WordSheet extends ConsumerWidget {
  const _WordSheet({
    required this.word,
    required this.sentence,
    required this.bookTitle,
    required this.entry,
    this.contextMeaning,
  });

  final String word;
  final String sentence;
  final String bookTitle;
  final DictionaryEntry? entry;
  final String? contextMeaning;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kit = Kit.of(context);
    final saved = ref.watch(notebookProvider).hasWord(word);
    final meaning = contextMeaning ?? entry?.senses.first.definition;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (contextMeaning != null)
        KitPanel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('IN THIS SENTENCE', style: kit.label.copyWith(color: kit.accent)),
            const SizedBox(height: 6),
            Text(contextMeaning!, style: kit.heading),
          ]),
        ),
      const SizedBox(height: 14),
      if (entry == null && contextMeaning == null)
        Text('No offline definition for “$word”.', style: kit.body)
      else if (entry != null) ...[
        Text('DICTIONARY', style: kit.label),
        const SizedBox(height: 8),
        for (final s in entry!.senses)
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
                  sentence: sentence,
                  bookTitle: bookTitle,
                ),
      ),
    ]);
  }
}
