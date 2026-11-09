import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/library.dart';
import '../../data/settings_provider.dart';

/// ≤ 60 seconds to the first card (UX_DESIGN.md §5.9): one value screen,
/// interests, then straight into a starter book. The daily goal is asked
/// later, after the first cards.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _step = 0;
  final Set<String> _interests = {};
  bool _starting = false;

  static const _options = [
    'Classics', 'Self-improvement', 'Science', 'History', 'Business', 'Fiction', 'Philosophy', 'Psychology',
    'Biography', 'Fantasy', 'Health', 'Poetry',
  ];

  Future<void> _start() async {
    setState(() => _starting = true);
    final library = ref.read(libraryProvider.notifier);
    final starter = await library.ensureStarterBook() ?? library.current;
    ref.read(settingsProvider.notifier).update((s) => s.copyWith(onboardingDone: true, interests: _interests.toList()));
    if (!mounted) return;
    context.go('/today');
    if (starter != null) context.push('/read/${starter.id}');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: _step == 0
              ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Spacer(),
                  const Icon(Icons.auto_stories, size: 56, color: Color(0xFFE08A2E)),
                  const SizedBox(height: 24),
                  Text('Read books in bite-sized cards.', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  Text('Swipe through real books, a few minutes a day. Build a reading habit that sticks.',
                      style: theme.textTheme.titleMedium),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      onPressed: () => setState(() => _step = 1),
                      child: const Text('Get started'),
                    ),
                  ),
                ])
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const SizedBox(height: 24),
                  Text('What do you like to read?', style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 4),
                  Text('Pick a few. We’ll start you with a short classic.', style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 20),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final o in _options)
                      FilterChip(
                        label: Text(o),
                        selected: _interests.contains(o),
                        onSelected: (v) => setState(() => v ? _interests.add(o) : _interests.remove(o)),
                      ),
                  ]),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      onPressed: _starting ? null : _start,
                      child: Text(_starting ? 'Preparing your first cards…' : 'Start reading'),
                    ),
                  ),
                ]),
        ),
      ),
    );
  }
}
