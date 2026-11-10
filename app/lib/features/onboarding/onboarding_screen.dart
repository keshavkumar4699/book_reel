import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/library.dart';
import '../../data/settings.dart';
import '../../data/settings_provider.dart';
import '../../ui/vibes.dart';

/// ≤ 60 seconds to the first card: a welcome over a live scene, pick a study
/// vibe, pick interests, then straight into a starter book. The daily goal is
/// asked later, after the first cards.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _step = 0;
  Vibe _vibe = Vibe.forest;
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
    ref.read(settingsProvider.notifier).update(
          (s) => s.copyWith(onboardingDone: true, interests: _interests.toList(), vibe: _vibe),
        );
    if (!mounted) return;
    context.go('/today');
    if (starter != null) context.push('/read/${starter.id}');
  }

  @override
  Widget build(BuildContext context) {
    final style = vibeStyles[_vibe]!;
    final palette = scenePalettes[_vibe];
    final fg = palette?.ink ?? const Color(0xFF1F1D1A);
    final shadows = palette?.textShadows;
    final titleStyle = TextStyle(color: fg, fontSize: 30, fontWeight: FontWeight.w800, height: 1.15, shadows: shadows);
    final bodyStyle = TextStyle(color: fg.withValues(alpha: 0.92), fontSize: 17, height: 1.4, shadows: shadows);
    Widget primary(String label, VoidCallback? onPressed) => SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              backgroundColor: style.accent,
              foregroundColor: Colors.black,
              textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            onPressed: onPressed,
            child: Text(label),
          ),
        );

    final steps = [
      // 1. Welcome
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Spacer(),
        Text('Scroll books\nlike reels.', style: titleStyle),
        const SizedBox(height: 14),
        Text('Real books in short, beautiful cards. A few calm minutes a day, and a habit that sticks.', style: bodyStyle),
        const SizedBox(height: 32),
        primary('Get started', () => setState(() => _step = 1)),
      ]),
      // 2. Vibe
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Spacer(),
        Text('Pick your study vibe', style: titleStyle),
        const SizedBox(height: 8),
        Text(style.tagline, style: bodyStyle),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          decoration: BoxDecoration(color: const Color(0xCCFFFFFF), borderRadius: BorderRadius.circular(24)),
          child: VibePickerRow(selected: _vibe, onSelected: (v) => setState(() => _vibe = v), height: 120),
        ),
        const SizedBox(height: 20),
        primary('Next', () => setState(() => _step = 2)),
      ]),
      // 3. Interests
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Spacer(),
        Text('What do you like to read?', style: titleStyle),
        const SizedBox(height: 8),
        Text('Pick a few. We’ll start you with a short classic.', style: bodyStyle),
        const SizedBox(height: 20),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final o in _options)
            FilterChip(
              label: Text(o),
              selected: _interests.contains(o),
              onSelected: (v) => setState(() => v ? _interests.add(o) : _interests.remove(o)),
            ),
        ]),
        const SizedBox(height: 28),
        primary(_starting ? 'Preparing your first cards…' : 'Start reading', _starting ? null : _start),
      ]),
    ];

    return Scaffold(
      body: Stack(children: [
        Positioned.fill(child: VibeBackground(vibe: _vibe)),
        // The scene's own calibrated shade keeps text readable on it.
        if (palette != null) Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: palette.scrim))),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              child: KeyedSubtree(key: ValueKey(_step), child: steps[_step]),
            ),
          ),
        ),
      ]),
    );
  }
}
