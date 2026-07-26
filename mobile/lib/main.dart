import 'dart:developer';

import 'package:flutter/material.dart';

import 'data/local/database.dart';
import 'data/remote/supabase_client.dart';
import 'features/auth/auth_gate.dart';
import 'features/sync/background_sync.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSupabase.initialize();
  try {
    await BackgroundSync.register();
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
    return MaterialApp(
      title: 'DeepRead',
      theme: AppTheme.dark(),
      home: AuthGate(db: db),
    );
  }
}
