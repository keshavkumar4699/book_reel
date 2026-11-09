import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/text/lexicon.dart';
import '../../data/notebook.dart';
import '../../services/tts.dart';

/// Half-height word sheet (UX_DESIGN.md §5.4): meaning in this sentence first,
/// then dictionary senses, pronunciation and "add to word list".
Future<void> showWordSheet(
  BuildContext context, {
  required String word,
  required String sentence,
  required String bookTitle,
  required Lexicon lexicon,
  String? contextMeaning,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _WordSheet(
      word: word,
      sentence: sentence,
      bookTitle: bookTitle,
      entry: lexicon.lookup(word),
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
    final theme = Theme.of(context);
    final saved = ref.watch(notebookProvider).hasWord(word);
    final meaning = contextMeaning ?? entry?.senses.first.definition;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        children: [
          Row(children: [
            Expanded(child: Text(entry?.lemma ?? word.toLowerCase(), style: theme.textTheme.headlineMedium)),
            IconButton(
              tooltip: 'Pronounce',
              icon: const Icon(Icons.volume_up_outlined),
              onPressed: () => Tts.instance.speak(word),
            ),
          ]),
          if (contextMeaning != null) ...[
            const SizedBox(height: 8),
            Text('In this sentence', style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
            const SizedBox(height: 4),
            Text(contextMeaning!, style: theme.textTheme.titleMedium),
          ],
          const SizedBox(height: 16),
          if (entry == null && contextMeaning == null)
            Text('No offline definition for “$word”.', style: theme.textTheme.bodyLarge)
          else if (entry != null) ...[
            Text('Dictionary', style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
            const SizedBox(height: 4),
            for (final s in entry!.senses)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text.rich(TextSpan(children: [
                    TextSpan(text: '${s.partOfSpeech}  ', style: const TextStyle(fontStyle: FontStyle.italic)),
                    TextSpan(text: s.definition),
                  ]), style: theme.textTheme.bodyLarge),
                  if (s.example != null)
                    Text('“${s.example}”', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ]),
              ),
          ],
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: saved || meaning == null
                ? null
                : () {
                    ref.read(notebookProvider.notifier).addWord(
                          word: entry?.lemma ?? word.toLowerCase(),
                          meaning: meaning,
                          sentence: sentence,
                          bookTitle: bookTitle,
                        );
                  },
            icon: Icon(saved ? Icons.check : Icons.add),
            label: Text(saved ? 'In your word list' : 'Add to word list'),
          ),
        ],
      ),
    );
  }
}
