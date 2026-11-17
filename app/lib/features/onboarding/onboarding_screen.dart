import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/library.dart';
import '../../data/settings.dart';
import '../../data/settings_provider.dart';
import '../../ui/kit.dart';

/// ≤ 60 seconds to the first card: a welcome, pick interests, then straight
/// into a starter book. The daily goal is asked later, after the first cards;
/// each book opens on a picture of its own. Onboarding wears the app's light
/// or dark theme; pictures belong to reading.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _step = 0;
  final Set<String> _interests = {};
  bool _starting = false;

  static const _options = readingGenres;

  Future<void> _start() async {
    setState(() => _starting = true);
    final library = ref.read(libraryProvider.notifier);
    final starter = await library.ensureStarterBook() ?? library.current;
    ref.read(settingsProvider.notifier).update(
          (s) => s.copyWith(onboardingDone: true, interests: _interests.toList()),
        );
    if (!mounted) return;
    // Straight into the first book, in the Reading tab.
    context.go(starter != null ? '/read/${starter.id}' : '/library');
  }

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    final titleStyle = kit.display;
    final bodyStyle = kit.body.copyWith(fontSize: 17, color: kit.inkSoft);
    Widget primary(String label, VoidCallback? onPressed) => KitButton(label: label, expand: true, onPressed: onPressed);

    final steps = [
      // 1. Welcome
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Spacer(),
        const CloroLogo(size: 56, wordmark: true),
        const SizedBox(height: 28),
        Text('Scroll books\nlike reels.', style: titleStyle),
        const SizedBox(height: 14),
        Text('Real books in short, beautiful cards. A few calm minutes a day, and a habit that sticks.', style: bodyStyle),
        const SizedBox(height: 32),
        primary('Get started', () => setState(() => _step = 1)),
      ]),
      // 2. Interests
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Spacer(),
        Text('What do you like to read?', style: titleStyle),
        const SizedBox(height: 8),
        Text('Pick up to 3. We’ll start you with a short classic.', style: bodyStyle),
        const SizedBox(height: 20),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final o in _options)
            KitChip(
              label: o,
              selected: _interests.contains(o),
              // Up to 3, as on the profile.
              onTap: !_interests.contains(o) && _interests.length >= 3
                  ? null
                  : () => setState(() => _interests.contains(o) ? _interests.remove(o) : _interests.add(o)),
            ),
        ]),
        const SizedBox(height: 28),
        primary(_starting ? 'Preparing your first cards…' : 'Start reading', _starting ? null : _start),
      ]),
    ];

    return AnnotatedRegion(
      value: kit.statusBar,
      child: Scaffold(
        backgroundColor: kit.base,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              child: KeyedSubtree(key: ValueKey(_step), child: steps[_step]),
            ),
          ),
        ),
      ),
    );
  }
}
