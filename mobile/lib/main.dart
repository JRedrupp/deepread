import 'dart:developer';

import 'package:flutter/material.dart';

import 'data/local/database.dart';
import 'data/remote/supabase_client.dart';
import 'features/auth/auth_gate.dart';
import 'features/settings/settings_repository.dart';
import 'features/sync/background_sync.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSupabase.initialize();
  final settings = await SettingsRepository.load();
  ThemeController.mode.value = settings.themeMode;
  try {
    await BackgroundSync.register(
      frequencyMinutes: settings.refreshFrequencyMinutes,
      wifiOnly: settings.wifiOnlySync,
    );
  } catch (e) {
    // Background registration failing (e.g. iOS without the
    // BGTaskSchedulerPermittedIdentifiers Info.plist entry — see
    // TODO.md) shouldn't prevent the app from starting. Manual "sync
    // now" still works either way.
    log('BackgroundSync.register failed: $e', name: 'main');
  }
  runApp(DeepReadApp(db: AppDatabase()));
}

class DeepReadApp extends StatelessWidget {
  const DeepReadApp({super.key, required this.db});

  final AppDatabase db;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, mode, _) => MaterialApp(
        title: 'DeepRead',
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: mode,
        home: AuthGate(db: db),
      ),
    );
  }
}
