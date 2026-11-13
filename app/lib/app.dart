import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'data/settings.dart';
import 'data/settings_provider.dart';
import 'data/sync_service.dart';
import 'services/billing.dart';
import 'features/friends/friends_screen.dart';
import 'features/library/library_screen.dart';
import 'features/notebook/notebook_screen.dart';
import 'features/notebook/word_review_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/reader/reader_screen.dart';
import 'features/settings/licenses_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/shell/home_shell.dart';
import 'features/today/today_screen.dart';
import 'ui/kit.dart';

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
      GoRoute(path: '/licenses', parentNavigatorKey: _rootKey, builder: (c, s) => const LicensesScreen()),
    ],
  );
});

class BookReelApp extends ConsumerStatefulWidget {
  const BookReelApp({super.key});

  @override
  ConsumerState<BookReelApp> createState() => _BookReelAppState();
}

class _BookReelAppState extends ConsumerState<BookReelApp> with WidgetsBindingObserver {
  // Screens outside the reader: plain light and dark (the reader wears its scene).
  static final _light = buildAppTheme(Kit.appLight);
  static final _dark = buildAppTheme(Kit.appDark);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Background sync with the server, when one is configured.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(syncServiceProvider).start();
      // Listen for Play purchases from the start (some complete while the app is closed).
      ref.read(billingProvider);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed || state == AppLifecycleState.paused) {
      ref.read(syncServiceProvider).syncNow();
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final appearance = ref.watch(settingsProvider.select((s) => s.appearance));
    return MaterialApp.router(
      title: 'Cloro',
      debugShowCheckedModeBanner: false,
      theme: _light,
      darkTheme: _dark,
      themeMode: switch (appearance) {
        AppAppearance.system => ThemeMode.system,
        AppAppearance.light => ThemeMode.light,
        AppAppearance.dark => ThemeMode.dark,
      },
      routerConfig: router,
    );
  }
}
