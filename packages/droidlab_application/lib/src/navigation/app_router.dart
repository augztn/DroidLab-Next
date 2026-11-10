import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../pages/feature_pages.dart';
import '../pages/operation_history_page.dart';
import '../shell/desktop_shell.dart';

Page<void> _animatedRoutePage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 190),
    reverseTransitionDuration: const Duration(milliseconds: 160),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.012),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(initialLocation: '/dashboard', routes: [
    ShellRoute(builder: (context, state, child) => DesktopShell(currentLocation: state.matchedLocation, child: child), routes: [
      GoRoute(path: '/dashboard', pageBuilder: (_, state) => _animatedRoutePage(state, const DashboardPage())),
      GoRoute(path: '/devices', pageBuilder: (_, state) => _animatedRoutePage(state, const DeviceManagerPage())),
      GoRoute(path: '/apps', pageBuilder: (_, state) => _animatedRoutePage(state, const AppManagerPage())),
      GoRoute(path: '/debloater', pageBuilder: (_, state) => _animatedRoutePage(state, const DebloaterPage())),
      GoRoute(path: '/firmware', pageBuilder: (_, state) => _animatedRoutePage(state, const PayloadExtractorPage())),
      GoRoute(path: '/payload', redirect: (_, __) => '/firmware'),
      GoRoute(path: '/adb', pageBuilder: (_, state) => _animatedRoutePage(state, const AdbToolkitPage())),
      GoRoute(path: '/fastboot', pageBuilder: (_, state) => _animatedRoutePage(state, const FastbootToolkitPage())),
      GoRoute(path: '/logs', pageBuilder: (_, state) => _animatedRoutePage(state, const LogsPage())),
      GoRoute(path: '/history', pageBuilder: (_, state) => _animatedRoutePage(state, const OperationHistoryPage())),
      GoRoute(path: '/settings', pageBuilder: (_, state) => _animatedRoutePage(state, const SettingsPage())),
      GoRoute(path: '/about', pageBuilder: (_, state) => _animatedRoutePage(state, const AboutPage())),
    ]),
  ]);
  ref.onDispose(router.dispose);
  return router;
});
