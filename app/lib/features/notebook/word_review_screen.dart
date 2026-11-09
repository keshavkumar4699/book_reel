import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/notebook.dart';

/// Spaced-repetition flashcards for saved words (DESIGN.md §2.5).
class WordReviewScreen extends ConsumerStatefulWidget {
  const WordReviewScreen({super.key});

  @override
  ConsumerState<WordReviewScreen> createState() => _WordReviewScreenState();
}

class _WordReviewScreenState extends ConsumerState<WordReviewScreen> {
  late final List<WordEntry> _queue = ref.read(notebookProvider).dueWords(DateTime.now());
  int _index = 0;
  bool _revealed = false;
  int _remembered = 0;

  void _answer(bool remembered) {
    ref.read(notebookProvider.notifier).reviewWord(_queue[_index].word, remembered: remembered);
    setState(() {
      if (remembered) _remembered++;
      _index++;
      _revealed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_index < _queue.length ? 'Review ${_index + 1} of ${_queue.length}' : 'Review')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _index >= _queue.length
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.check_circle_outline, size: 64),
                    const SizedBox(height: 16),
                    Text(_queue.isEmpty ? 'Nothing to review right now' : 'Done! $_remembered of ${_queue.length} remembered',
                        style: theme.textTheme.titleLarge),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Back')),
                  ]),
                )
              : Column(children: [
                  const Spacer(),
                  Text(_queue[_index].word, style: theme.textTheme.displaySmall),
                  const SizedBox(height: 16),
                  if (_queue[_index].sentence.isNotEmpty)
                    Text('“${_queue[_index].sentence}”',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(fontFamily: 'Literata', fontStyle: FontStyle.italic)),
                  const SizedBox(height: 24),
                  if (_revealed) Text(_queue[_index].meaning, textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
                  const Spacer(),
                  if (!_revealed)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(onPressed: () => setState(() => _revealed = true), child: const Text('Show meaning')),
                    )
                  else
                    Row(children: [
                      Expanded(child: OutlinedButton(onPressed: () => _answer(false), child: const Text('Still learning'))),
                      const SizedBox(width: 12),
                      Expanded(child: FilledButton(onPressed: () => _answer(true), child: const Text('I knew it'))),
                    ]),
                ]),
        ),
      ),
    );
  }
}
