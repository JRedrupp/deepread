import 'dart:io';

import '../../data/local/database.dart';

/// Deletes every locally cached row and file for the signed-out user:
/// [AppDatabase.localArticles] and [AppDatabase.localFeeds] rows, then the
/// unzipped article files under [articlesDir].
///
/// Takes the DB and directory as parameters (rather than resolving
/// `getApplicationDocumentsDirectory()` internally) so this is unit-testable
/// with `AppDatabase.forTesting(NativeDatabase.memory())` + a plain temp
/// `Directory` — no platform channels, no Supabase.
Future<void> resetLocalData({
  required AppDatabase db,
  required Directory articlesDir,
}) async {
  await db.transaction(() async {
    await db.delete(db.localArticles).go();
    await db.delete(db.localFeeds).go();
    // Must be cleared too: leaving the sync watermark behind would make
    // the next sync (for this or a different account) only fetch articles
    // rendered after that stale point, silently missing everything older.
    await db.delete(db.syncState).go();
  });

  if (await articlesDir.exists()) {
    await articlesDir.delete(recursive: true);
  }
}
