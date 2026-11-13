import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/notebook.dart';
import '../../ui/kit.dart';

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
    final kit = Kit.of(context);
    final done = _index >= _queue.length;
    final height = MediaQuery.sizeOf(context).height;
    return KitPage(
      title: done ? 'Review' : 'Review ${_index + 1} of ${_queue.length}',
      children: [
        if (done)
          KitEmpty(
            emoji: '✅',
            title: _queue.isEmpty ? 'Nothing to review right now' : 'Done! $_remembered of ${_queue.length} remembered',
            action: KitButton(label: 'Back', onPressed: () => Navigator.pop(context)),
          )
        else ...[
          SizedBox(height: height * 0.06),
          KitPanel(
            padding: const EdgeInsets.fromLTRB(22, 32, 22, 28),
            child: Column(children: [
              Text(_queue[_index].word, textAlign: TextAlign.center, style: kit.display),
              const SizedBox(height: 16),
              if (_queue[_index].sentence.isNotEmpty)
                Text('“${_queue[_index].sentence}”',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: 'Literata', fontStyle: FontStyle.italic, fontSize: 16, height: 1.45, color: kit.inkSoft)),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: _revealed
                    ? Padding(
                        padding: const EdgeInsets.only(top: 22),
                        child: Text(_queue[_index].meaning, textAlign: TextAlign.center, style: kit.heading),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ]),
          ),
          const SizedBox(height: 24),
          if (!_revealed)
            KitButton(label: 'Show meaning', expand: true, onPressed: () => setState(() => _revealed = true))
          else
            Row(children: [
              Expanded(child: KitButton.secondary(label: 'Still learning', expand: true, onPressed: () => _answer(false))),
              const SizedBox(width: 12),
              Expanded(child: KitButton(label: 'I knew it', expand: true, onPressed: () => _answer(true))),
            ]),
        ],
      ],
    );
  }
}
