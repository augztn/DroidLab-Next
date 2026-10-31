import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../pages/workspace_page.dart';
import '../shell/desktop_shell.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/dashboard',
    routes: [
      ShellRoute(
        builder: (context, state, child) => DesktopShell(
          currentLocation: state.matchedLocation,
          child: child,
        ),
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (_, __) => const WorkspacePage(
              title: 'Dashboard',
              description: 'Device readiness, runtime health and recent operations.',
            ),
          ),
          GoRoute(
            path: '/devices',
            builder: (_, __) => const WorkspacePage(
              title: 'Device Manager',
              description: 'Connected ADB and Fastboot devices will appear here when the backend bridge is available.',
            ),
          ),
          GoRoute(
            path: '/firmware',
            builder: (_, __) => const WorkspacePage(
              title: 'Firmware Explorer',
              description: 'Inspect OTA packages and review partition metadata.',
            ),
          ),
          GoRoute(
            path: '/payload',
            builder: (_, __) => const WorkspacePage(
              title: 'Payload Extractor',
              description: 'Inspect payload.bin and OTA ZIP files, select partitions and manage extraction output.',
            ),
          ),
          GoRoute(
            path: '/adb',
            builder: (_, __) => const WorkspacePage(
              title: 'ADB Toolkit',
              description: 'Device diagnostics, shell workflows, logcat, sideload and bugreports.',
            ),
          ),
          GoRoute(
            path: '/fastboot',
            builder: (_, __) => const WorkspacePage(
              title: 'Fastboot Toolkit',
              description: 'Review target device, partition and command before maintenance or flashing.',
            ),
          ),
          GoRoute(
            path: '/logs',
            builder: (_, __) => const WorkspacePage(
              title: 'Logs & Diagnostics',
              description: 'Application and backend diagnostics will be streamed here.',
            ),
          ),
          GoRoute(
            path: '/history',
            builder: (_, __) => const WorkspacePage(
              title: 'Operation History',
              description: 'Completed and interrupted operations will be recorded here.',
            ),
          ),
          GoRoute(
            path: '/settings',
            builder: (_, __) => const WorkspacePage(
              title: 'Settings',
              description: 'Tool paths, backend runtime and application preferences.',
            ),
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
