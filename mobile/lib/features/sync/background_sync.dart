import 'package:workmanager/workmanager.dart';

import '../../data/local/database.dart';
import '../../data/remote/supabase_client.dart';
import 'sync_service.dart';

const _syncTaskName = 'deepread-periodic-sync';

/// Runs in a separate background isolate (Android WorkManager / iOS
/// BGTaskScheduler under the hood) — nothing from the running app's memory
/// is available here, so Supabase and the local DB are reopened fresh.
@pragma('vm:entry-point')
void backgroundSyncDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    await AppSupabase.initialize();
    final db = AppDatabase();
    try {
      await SyncService(db).syncNow();
      return true;
    } catch (_) {
      return false;
    } finally {
      await db.close();
    }
  });
}

class BackgroundSync {
  BackgroundSync._();

  static Future<void> register() async {
    await Workmanager().initialize(backgroundSyncDispatcher);
    await Workmanager().registerPeriodicTask(
      _syncTaskName,
      _syncTaskName,
      // 15 minutes is Android WorkManager's minimum periodic interval;
      // iOS treats this as a hint, not a guarantee (BGTaskScheduler decides
      // actual timing). See TODO.md — iOS also needs Info.plist entries
      // (BGTaskSchedulerPermittedIdentifiers) that aren't set up yet.
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
    );
  }
}
