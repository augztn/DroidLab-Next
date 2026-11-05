import 'package:droidlab_application/droidlab_application.dart';
import 'package:droidlab_design_system/droidlab_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: DroidLabApp()));
}

class DroidLabApp extends ConsumerWidget {
  const DroidLabApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final settings = ref.watch(droidLabSettingsProvider);
    return MaterialApp.router(
      title: 'DroidLab',
      debugShowCheckedModeBanner: false,
      theme: DroidLabTheme.light(
        themeName: settings.valueOrNull?.theme ?? 'cyberpunk_glass',
      ),
      darkTheme: DroidLabTheme.dark(
        themeName: settings.valueOrNull?.theme ?? 'cyberpunk_glass',
      ),
      themeMode: switch (settings.valueOrNull?.themeMode ?? 'dark') {
        'light' => ThemeMode.light,
        'system' => ThemeMode.system,
        _ => ThemeMode.dark,
      },
      routerConfig: router,
    );
  }
}
