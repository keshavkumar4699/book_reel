import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'data/settings_provider.dart';
import 'features/friends/friends_screen.dart';
import 'features/library/library_screen.dart';
import 'features/notebook/notebook_screen.dart';
import 'features/notebook/word_review_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/reader/reader_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/shell/home_shell.dart';
import 'features/today/today_screen.dart';
import 'ui/theme.dart';

final _rootKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/today',
    redirect: (context, state) {
      final done = ref.read(settingsProvider).onboardingDone;
      final atOnboarding = state.matchedLocation == '/onboarding';
      if (!done && !atOnboarding && !state.matchedLocation.startsWith('/read/')) return '/onboarding';
      return null;
    },
    routes: [
      GoRoute(path: '/onboarding', builder: (context, state) => const OnboardingScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/today', builder: (c, s) => const TodayScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/library', builder: (c, s) => const LibraryScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/notebook', builder: (c, s) => const NotebookScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/friends', builder: (c, s) => const FriendsScreen())]),
        ],
      ),
      GoRoute(
        path: '/read/:bookId',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => ReaderScreen(
          bookId: state.pathParameters['bookId']!,
          startSid: state.uri.queryParameters['sid'],
        ),
      ),
      GoRoute(path: '/settings', parentNavigatorKey: _rootKey, builder: (c, s) => const SettingsScreen()),
      GoRoute(path: '/profile', parentNavigatorKey: _rootKey, builder: (c, s) => const ProfileScreen()),
      GoRoute(path: '/review', parentNavigatorKey: _rootKey, builder: (c, s) => const WordReviewScreen()),
    ],
  );
});

class BookReelApp extends ConsumerWidget {
  const BookReelApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'BookReel',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(brightness: Brightness.light),
      darkTheme: buildAppTheme(brightness: Brightness.dark),
      routerConfig: router,
    );
  }
}
