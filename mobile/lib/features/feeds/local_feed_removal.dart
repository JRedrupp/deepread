import 'dart:io';

import 'package:path/path.dart' as p;

import '../../data/local/database.dart';

/// Deletes one feed's [AppDatabase.localFeeds]/[AppDatabase.localArticles]
/// rows and its downloaded articles' unzipped directories, leaving every
/// other feed untouched.
///
/// [docsDir] is the app documents directory — each article's `localPath` is
/// already relative to it (e.g. `articles/<id>`), matching how
/// `sync_service.dart`'s `_downloadAndStore` builds the same path.
Future<void> removeLocalFeedData({
  required AppDatabase db,
  required Directory docsDir,
  required String feedId,
}) async {
  final articles =
      await (db.select(db.localArticles)..where((a) => a.feedId.equals(feedId))).get();

  // Drift never enables PRAGMA foreign_keys here, so this ordering (children
  // before parent) is a discipline we must uphold ourselves — SQLite won't
  // enforce or complain if it's reversed.
  await db.transaction(() async {
    await (db.delete(db.localArticles)..where((a) => a.feedId.equals(feedId))).go();
    await (db.delete(db.localFeeds)..where((f) => f.id.equals(feedId))).go();
  });

  for (final article in articles) {
    final localPath = article.localPath;
    if (localPath == null) continue; // paywalled — no on-disk folder
    final dir = Directory(p.join(docsDir.path, localPath));
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
