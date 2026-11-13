import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/notebook.dart';
import '../../ui/kit.dart';
import '../reader/reader_screen.dart';

/// Five tabs and a floating dock (Cloro plan §9): Reading (the reels of the
/// current book, wearing its scene), Library, Notebook, Today and Profile in
/// the app's light or dark theme. While reading, the dock hides with the
/// reader's other controls (focus mode).
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kit = Kit.of(context);
    final due = ref.watch(notebookProvider.select((n) => n.dueWords(DateTime.now()).length));
    final focus = shell.currentIndex == 0 && !ref.watch(readerChromeProvider);
    return AnnotatedRegion(
      value: kit.statusBar,
      child: Scaffold(
        backgroundColor: kit.base,
        body: Stack(children: [
          Positioned.fill(child: shell),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              ignoring: focus,
              child: AnimatedSlide(
                offset: focus ? const Offset(0, 1.2) : Offset.zero,
                duration: Duration(milliseconds: MediaQuery.disableAnimationsOf(context) ? 0 : 240),
                curve: Curves.easeOutCubic,
                child: ExcludeSemantics(
                  excluding: focus,
                  child: KitNavBar(
                    index: shell.currentIndex,
                    // Tapping the Reading tab again keeps your place (no reset).
                    onSelect: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex && i != 0),
                    items: [
                      const KitNavItem(Icons.play_circle_outline_rounded, Icons.play_circle_rounded, 'Reading'),
                      const KitNavItem(Icons.auto_stories_outlined, Icons.auto_stories_rounded, 'Library'),
                      KitNavItem(Icons.book_outlined, Icons.book_rounded, 'Notebook', badge: due),
                      const KitNavItem(Icons.wb_sunny_outlined, Icons.wb_sunny_rounded, 'Today'),
                      const KitNavItem(Icons.person_outline_rounded, Icons.person_rounded, 'Profile'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
