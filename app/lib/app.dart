import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'data/settings.dart';
import 'data/settings_provider.dart';
import 'data/sync_service.dart';
import 'services/billing.dart';
import 'features/friends/friends_screen.dart';
import 'features/settings/legal_screen.dart';
import 'features/social/people_screen.dart';
import 'features/social/reader_profile_screen.dart';
import 'features/library/library_screen.dart';
import 'features/notebook/notebook_screen.dart';
import 'features/notebook/word_review_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/reader/reading_tab.dart';
import 'features/settings/licenses_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/shell/home_shell.dart';
import 'features/today/today_screen.dart';
import 'ui/kit.dart';

final _rootKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootKey,
    // Reading is the main tab: the app opens on the book you're reading.
    initialLocation: '/reading',
    redirect: (context, state) {
      final done = ref.read(settingsProvider).onboardingDone;
      final atOnboarding = state.matchedLocation == '/onboarding';
      // A link to a passage (e.g. a shared quote) opens before onboarding too.
      final deepLink = state.matchedLocation.startsWith('/read/') || state.uri.queryParameters.containsKey('book');
      if (!done && !atOnboarding && !deepLink) return '/onboarding';
      return null;
    },
    routes: [
      GoRoute(path: '/onboarding', builder: (context, state) => const OnboardingScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => HomeShell(shell: shell),
        // Reading · Library · Notebook · Today · Profile.
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/reading',
              builder: (c, s) => ReadingTab(bookId: s.uri.queryParameters['book'], startSid: s.uri.queryParameters['sid']),
            ),
          ]),
          StatefulShellBranch(routes: [GoRoute(path: '/library', builder: (c, s) => const LibraryScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/notebook', builder: (c, s) => const NotebookScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/today', builder: (c, s) => const TodayScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/profile', builder: (c, s) => const ProfileScreen())]),
        ],
      ),
      // Links to a book (and a passage in it) open it in the Reading tab.
      GoRoute(
        path: '/read/:bookId',
        redirect: (context, state) {
          final sid = state.uri.queryParameters['sid'];
          return Uri(path: '/reading', queryParameters: {'book': state.pathParameters['bookId']!, 'sid': ?sid}).toString();
        },
      ),
      GoRoute(path: '/friends', parentNavigatorKey: _rootKey, builder: (c, s) => const FriendsScreen(asPage: true)),
      // Followers and following ("me", a user id or "@handle"), and another reader's profile.
      GoRoute(
        path: '/people/:userId',
        parentNavigatorKey: _rootKey,
        builder: (c, s) => PeopleScreen(
          userId: s.pathParameters['userId']!,
          tab: s.uri.queryParameters['tab'] == 'following' ? PeopleTab.following : PeopleTab.followers,
          name: s.uri.queryParameters['name'],
        ),
      ),
      GoRoute(path: '/u/:id', parentNavigatorKey: _rootKey, builder: (c, s) => ReaderProfileScreen(id: s.pathParameters['id']!)),
      GoRoute(path: '/settings', parentNavigatorKey: _rootKey, builder: (c, s) => const SettingsScreen()),
      GoRoute(path: '/review', parentNavigatorKey: _rootKey, builder: (c, s) => const WordReviewScreen()),
      GoRoute(path: '/licenses', parentNavigatorKey: _rootKey, builder: (c, s) => const LicensesScreen()),
      GoRoute(
        path: '/legal/:doc',
        parentNavigatorKey: _rootKey,
        builder: (c, s) => LegalScreen(doc: LegalDoc.byName(s.pathParameters['doc']!) ?? LegalDoc.privacy),
      ),
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
