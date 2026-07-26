import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' show Value;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/local/database.dart';
import '../../data/remote/supabase_client.dart';

/// Pulls down anything the backend worker has rendered for this user's
/// subscribed feeds: refreshes local feed metadata, then downloads and
/// unzips any newly-`ready` articles this device doesn't have yet.
///
/// This is deliberately lightweight (a Postgres query + a few file
/// downloads) — no rendering happens on-device, which is the whole reason
/// the cloud pipeline exists in the first place. Safe to call from a
/// background fetch callback under OS time limits.
class SyncService {
  const SyncService(this.db);

  final AppDatabase db;

  Future<void> syncNow() async {
    final userId = AppSupabase.client.auth.currentUser?.id;
    if (userId == null) return;

    await _syncFeeds(userId);
    await _syncArticles();
  }

  Future<void> _syncFeeds(String userId) async {
    final rows = await AppSupabase.client
        .from('user_feed_subscriptions')
        .select('feeds(id, url, title)')
        .eq('user_id', userId);

    for (final row in rows as List) {
      final feed = row['feeds'] as Map<String, dynamic>;
      await db.into(db.localFeeds).insertOnConflictUpdate(
            LocalFeedsCompanion.insert(
              id: feed['id'] as String,
              url: feed['url'] as String,
              title: Value(feed['title'] as String?),
            ),
          );
    }
  }

  Future<void> _syncArticles() async {
    // RLS on `articles` already scopes this to feeds the current user is
    // subscribed to — see supabase/migrations/0001_init.sql.
    final rows = await AppSupabase.client.from('articles').select().eq('status', 'ready');

    for (final row in rows as List) {
      final article = row as Map<String, dynamic>;
      final id = article['id'] as String;
      final storagePath = article['storage_path'] as String?;

      final alreadyDownloaded = await (db.select(db.localArticles)..where((a) => a.id.equals(id)))
          .getSingleOrNull();
      // A summary-only row (from a previous paywalled sync) should still be
      // upgraded to a full download if the backend later renders it — see
      // TODO.md's "no re-download path when re-rendered" gap.
      final needsUpgradeToFullDownload = alreadyDownloaded?.localPath == null && storagePath != null;
      if (alreadyDownloaded != null && !needsUpgradeToFullDownload) continue;

      if (storagePath == null) {
        // Paywalled article — only an RSS summary is available, no
        // rendered HTML to download.
        await _insertPaywalledArticle(article);
      } else {
        await _downloadAndStore(article, storagePath);
      }
    }
  }

  Future<void> _insertPaywalledArticle(Map<String, dynamic> article) async {
    await db.into(db.localArticles).insertOnConflictUpdate(
          LocalArticlesCompanion.insert(
            id: article['id'] as String,
            feedId: article['feed_id'] as String,
            title: article['title'] as String? ?? '(untitled)',
            byline: Value(article['byline'] as String?),
            publishedAt: Value(_parseTimestamp(article['published_at'] as String?)),
            downloadedAt: DateTime.now(),
            summary: Value(article['summary'] as String?),
          ),
        );
  }

  Future<void> _downloadAndStore(Map<String, dynamic> article, String storagePath) async {
    final id = article['id'] as String;
    final bytes = await AppSupabase.client.storage.from('articles').download(storagePath);

    final docsDir = await getApplicationDocumentsDirectory();
    final articleDir = Directory(p.join(docsDir.path, 'articles', id));
    await articleDir.create(recursive: true);
    await _unzipInto(bytes, articleDir);

    await db.into(db.localArticles).insertOnConflictUpdate(
          LocalArticlesCompanion.insert(
            id: id,
            feedId: article['feed_id'] as String,
            title: article['title'] as String? ?? '(untitled)',
            byline: Value(article['byline'] as String?),
            publishedAt: Value(_parseTimestamp(article['published_at'] as String?)),
            downloadedAt: DateTime.now(),
            localPath: Value(p.join('articles', id)),
          ),
        );
  }

  Future<void> _unzipInto(Uint8List zipBytes, Directory targetDir) async {
    final archive = ZipDecoder().decodeBytes(zipBytes);
    for (final file in archive) {
      if (!file.isFile) continue;
      final outFile = File(p.join(targetDir.path, file.name));
      await outFile.parent.create(recursive: true);
      await outFile.writeAsBytes(file.content as List<int>);
    }
  }

  DateTime? _parseTimestamp(String? iso) => iso == null ? null : DateTime.tryParse(iso);
}
