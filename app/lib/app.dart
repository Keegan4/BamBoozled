import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/layout/adaptive_scaffold.dart';
import 'core/layout/compact_scale.dart';
import 'core/theme/panda_theme.dart';
import 'data/providers.dart';
import 'features/calendar/calendar_page.dart';
import 'features/notes/binder_page.dart';
import 'features/notes/notes_page.dart';
import 'features/settings/settings_page.dart';
import 'features/tasks/all_tasks_page.dart';
import 'features/welcome/welcome_page.dart';

GoRouter buildRouter({String initialLocation = '/'}) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    ShellRoute(
      builder: (context, state, child) => AdaptiveScaffold(location: state.uri.path, child: child),
      routes: [
        GoRoute(
          path: '/',
          pageBuilder: (_, _) => const NoTransitionPage(child: WelcomePage()),
        ),
        GoRoute(
          path: '/tasks',
          pageBuilder: (_, _) => const NoTransitionPage(child: AllTasksPage()),
        ),
        GoRoute(
          path: '/calendar',
          pageBuilder: (_, _) => const NoTransitionPage(child: CalendarPage()),
        ),
        GoRoute(
          path: '/notes',
          pageBuilder: (_, _) => const NoTransitionPage(child: NotesPage()),
          routes: [
            GoRoute(
              path: 'binder',
              pageBuilder: (_, _) => const NoTransitionPage(child: BinderPage()),
            ),
          ],
        ),
        GoRoute(
          path: '/settings',
          pageBuilder: (_, _) => const NoTransitionPage(child: SettingsPage()),
        ),
      ],
    ),
  ],
);

final routerProvider = Provider<GoRouter>((ref) {
  final router = buildRouter();
  ref.onDispose(router.dispose);
  return router;
});

class BamBoozledApp extends ConsumerWidget {
  const BamBoozledApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keep background sync running while the app is open.
    ref.watch(syncServiceProvider);
    ref.watch(repeatSpawnerProvider);
    ref.watch(canvasAutoRefreshProvider);
    final compact = ref.watch(compactPhoneLayoutProvider);
    return MaterialApp.router(
      title: 'BamBoozled',
      debugShowCheckedModeBanner: false,
      theme: buildPandaTheme(),
      darkTheme: buildPandaTheme(brightness: Brightness.dark),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) => CompactScale(enabled: compact, child: child!),
    );
  }
}
