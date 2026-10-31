import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../pages/feature_pages.dart';
import '../pages/operation_history_page.dart';
import '../pages/operation_history_page.dart';
import '../shell/desktop_shell.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(initialLocation: '/dashboard', routes: [
    ShellRoute(builder: (context, state, child) => DesktopShell(currentLocation: state.matchedLocation, child: child), routes: [
      GoRoute(path: '/dashboard', builder: (_, __) => const DashboardPage()),
      GoRoute(path: '/devices', builder: (_, __) => const DeviceManagerPage()),
      GoRoute(path: '/firmware', builder: (_, __) => const PayloadExtractorPage()),
      GoRoute(path: '/payload', builder: (_, __) => const PayloadExtractorPage()),
      GoRoute(path: '/adb', builder: (_, __) => const AdbToolkitPage()),
      GoRoute(path: '/fastboot', builder: (_, __) => const FastbootToolkitPage()),
      GoRoute(path: '/logs', builder: (_, __) => const LogsPage()),
      GoRoute(path: '/history', builder: (_, __) => const OperationHistoryPage()),
      GoRoute(path: '/settings', builder: (_, __) => const SettingsPage()),
    ]),
  ]);
  ref.onDispose(router.dispose);
  return router;
});
