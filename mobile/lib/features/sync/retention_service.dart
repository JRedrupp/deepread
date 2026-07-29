import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../../data/local/database.dart';

/// Frees on-device storage by evicting downloaded article content — either
/// automatically (auto-expire read articles, per-feed cap) or on demand
/// ("Clear downloaded articles" in Settings). Takes [db]/[articlesDir] as
/// constructor params (same DI pattern as `resetLocalData`) so it's
/// unit-testable with an in-memory drift DB and a plain temp directory.
class RetentionService {
  const RetentionService(this.db, {required this.articlesDir});

  final AppDatabase db;
  final Directory articlesDir;

  /// Sweeps existing downloaded articles against the given thresholds.
  /// Either or both may be null (disabled). Reads current settings fresh
  /// each call — this must work correctly called from the background sync
  /// isolate, which has no access to the running app's in-memory state.
  Future<void> applyAutoPolicy({int? expireReadAfterDays, int? capPerFeed, DateTime? now}) async {
    if (expireReadAfterDays != null) {
      await _evictExpiredRead(expireReadAfterDays, now ?? DateTime.now());
    }
    if (capPerFeed != null) {
      await _evictOverCap(capPerFeed);
    }
  }

  Future<void> _evictExpiredRead(int expireReadAfterDays, DateTime now) async {
    final cutoff = now.subtract(Duration(days: expireReadAfterDays));
    final rows = await (db.select(db.localArticles)
          ..where(
            (a) => a.localPath.isNotNull() & a.isRead.equals(true) & a.downloadedAt.isSmallerThanValue(cutoff),
          ))
        .get();
    for (final row in rows) {
      await _evict(row);
    }
  }

  /// A post-sync sweep, not a pre-fetch filter — an article can still be
  /// downloaded once and then immediately evicted if it pushes its feed
  /// over the cap. Simpler than reworking the fetch query to be
  /// feed/cap-aware, and the cost is one wasted download, not a
  /// correctness issue.
  Future<void> _evictOverCap(int capPerFeed) async {
    final active = await (db.select(db.localArticles)..where((a) => a.localPath.isNotNull())).get();
    final byFeed = <String, List<LocalArticle>>{};
    for (final row in active) {
      byFeed.putIfAbsent(row.feedId, () => []).add(row);
    }
    for (final rows in byFeed.values) {
      if (rows.length <= capPerFeed) continue;
      rows.sort((a, b) => (b.publishedAt ?? b.downloadedAt).compareTo(a.publishedAt ?? a.downloadedAt));
      for (final row in rows.skip(capPerFeed)) {
        await _evict(row);
      }
    }
  }

  /// Evicts every currently-downloaded article. The sync watermark is
  /// deliberately left untouched — resetting it would trigger a full
  /// re-fetch storm on the next sync.
  Future<void> clearAllDownloaded() async {
    final rows = await (db.select(db.localArticles)..where((a) => a.localPath.isNotNull())).get();
    for (final row in rows) {
      await _evict(row);
    }
  }

  Future<int> computeStorageBytes() async {
    if (!await articlesDir.exists()) return 0;
    var total = 0;
    await for (final entity in articlesDir.list(recursive: true)) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }

  Future<void> _evict(LocalArticle article) async {
    final dir = Directory(p.join(articlesDir.path, article.id));
    if (await dir.exists()) await dir.delete(recursive: true);
    await (db.update(db.localArticles)..where((a) => a.id.equals(article.id))).write(
      const LocalArticlesCompanion(localPath: Value(null), evicted: Value(true)),
    );
  }
}
