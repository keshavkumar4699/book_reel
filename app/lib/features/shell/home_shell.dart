import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/notebook.dart';
import '../../ui/kit.dart';

/// Four destinations on one scene (UX_DESIGN.md §4, Revision 6): the
/// reader's scene stays behind every tab and a floating dock switches them.
/// The scene moves only on Today; lists sit on a still frame of it.
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kit = Kit.of(context);
    final due = ref.watch(notebookProvider.select((n) => n.dueWords(DateTime.now()).length));
    return AnnotatedRegion(
      value: kit.statusBar,
      child: Scaffold(
        backgroundColor: kit.base,
        body: Stack(children: [
          Positioned.fill(child: SceneBackdrop(animate: shell.currentIndex == 0)),
          Positioned.fill(child: shell),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: KitNavBar(
              index: shell.currentIndex,
              onSelect: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
              items: [
                const KitNavItem(Icons.wb_sunny_outlined, Icons.wb_sunny_rounded, 'Today'),
                const KitNavItem(Icons.auto_stories_outlined, Icons.auto_stories_rounded, 'Library'),
                KitNavItem(Icons.book_outlined, Icons.book_rounded, 'Notebook', badge: due),
                const KitNavItem(Icons.people_outline_rounded, Icons.people_rounded, 'Friends'),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
