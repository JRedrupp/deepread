import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' show Value;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/local/database.dart';
import '../../data/remote/supabase_client.dart';
import '../settings/settings_repository.dart';
import 'retention_service.dart';

/// A remote `articles` row as returned by the `fetchReadyArticles` query,
/// parsed out of the raw PostgREST JSON map once so downstream logic
/// doesn't repeat `as String?` casts.
class RemoteArticleRow {
  RemoteArticleRow.fromRow(Map<String, dynamic> row)
      : id = row['id'] as String,
        feedId = row['feed_id'] as String,
        title = row['title'] as String?,
        byline = row['byline'] as String?,
        summary = row['summary'] as String?,
        publishedAt = row['published_at'] as String?,
        renderedAt = row['rendered_at'] as String?,
        storagePath = row['storage_path'] as String?;

  final String id;
  final String feedId;
  final String? title;
  final String? byline;
  final String? summary;
  final String? publishedAt;
  final String? renderedAt;
  final String? storagePath;
}

/// What to do with one remote article row, given what (if anything) is
/// already stored locally for it.
enum ArticleSyncAction {
  /// Nothing downloadable yet — insert/update a summary-only row.
  insertPaywalled,

  /// Download and unzip the rendered content (new article, paywall→full
  /// upgrade, or a genuine re-render of an already-downloaded article).
  download,

  /// A pre-migration row already has this article fully downloaded but
  /// has no recorded [LocalArticle.renderedAt] to compare against. There's
  /// no reliable "did it change" signal for it, so don't redownload —
  /// just backfill the column so future passes can version-check it.
  backfillRenderedAt,

  /// Local copy is already at least as new as the remote row.
  skip,
}

/// Pure decision logic for one article, given the matching local row (or
/// null if never seen before). Kept separate from I/O so it's directly
/// unit-testable without a database or network.
ArticleSyncAction decideArticleSyncAction({
  required RemoteArticleRow remote,
  required LocalArticle? local,
}) {
  if (local == null) {
    return remote.storagePath == null ? ArticleSyncAction.insertPaywalled : ArticleSyncAction.download;
  }

  final localRenderedAt = local.renderedAt;
  if (localRenderedAt != null) {
    // Defensive: the backend always sets rendered_at on a ready article,
    // so remote.renderedAt should never be null here in practice. If it
    // somehow is, there's nothing newer to act on — skip rather than risk
    // redownloading on every pass.
    final remoteRenderedAt = remote.renderedAt;
    final remoteIsNewer =
        remoteRenderedAt != null && DateTime.parse(remoteRenderedAt).isAfter(DateTime.parse(localRenderedAt));
    if (!remoteIsNewer) return ArticleSyncAction.skip;
    return remote.storagePath == null ? ArticleSyncAction.insertPaywalled : ArticleSyncAction.download;
  }

  // local.renderedAt == null: a pre-migration row.
  if (local.localPath != null && remote.storagePath != null) {
    return ArticleSyncAction.backfillRenderedAt;
  }
  // Otherwise: still paywalled pre-migration (no reliable version to
  // compare, but nothing downloaded to lose either — fall through and
  // treat like new), or the existing paywall→full upgrade case.
  return remote.storagePath == null ? ArticleSyncAction.insertPaywalled : ArticleSyncAction.download;
}

Future<List<Map<String, dynamic>>> _defaultFetchReadyArticles({String? since}) async {
  // RLS on `articles` already scopes this to feeds the current user is
  // subscribed to — see supabase/migrations/0001_init.sql.
  var query = AppSupabase.client
      .from('articles')
      .select('id, feed_id, title, byline, summary, published_at, rendered_at, storage_path')
      .eq('status', 'ready');
  if (since != null) query = query.gt('rendered_at', since);
  final rows = await query;
  return (rows as List).cast<Map<String, dynamic>>();
}

Future<Uint8List> _defaultDownloadArticleZip(String storagePath) {
  return AppSupabase.client.storage.from('articles').download(storagePath);
}

/// Whether this device has a pending full-catalog fetch to do, set by
/// [FeedRepository.subscribe] whenever it (re)subscribes to a feed on this
/// device. See [SyncState.needsFullFetch] for why this exists as a
/// separate signal from [SyncService]'s own newly-subscribed-elsewhere
/// detection.
Future<bool> hasPendingFullFetch(AppDatabase db) async {
  final state = await (db.select(db.syncState)..where((s) => s.id.equals(0))).getSingleOrNull();
  return state?.needsFullFetch ?? false;
}

/// Sets the pending-full-fetch signal read by [hasPendingFullFetch].
/// Preserves any existing watermark — only `needsFullFetch` is written.
Future<void> markPendingFullFetch(AppDatabase db) async {
  await db.into(db.syncState).insertOnConflictUpdate(
        const SyncStateCompanion(id: Value(0), needsFullFetch: Value(true)),
      );
}

/// Clears the pending-full-fetch signal. Called by [SyncService.syncNow]
/// only after a full fetch has completed without any row failing, so a
/// failed pass safely retries with the signal still set next time.
Future<void> clearPendingFullFetch(AppDatabase db) async {
  await (db.update(db.syncState)..where((s) => s.id.equals(0)))
      .write(const SyncStateCompanion(needsFullFetch: Value(false)));
}

Future<void> _defaultRecordLastSynced(DateTime time) async {
  final settings = await SettingsRepository.load();
  await settings.setLastSyncedAt(time);
}

Future<void> _defaultApplyRetentionPolicy(AppDatabase db) async {
  final settings = await SettingsRepository.load();
  final expireDays = settings.retentionExpireReadAfterDays;
  final capPerFeed = settings.retentionCapPerFeed;
  if (expireDays == null && capPerFeed == null) return;

  final docsDir = await getApplicationDocumentsDirectory();
  final retention = RetentionService(db, articlesDir: Directory(p.join(docsDir.path, 'articles')));
  await retention.applyAutoPolicy(expireReadAfterDays: expireDays, capPerFeed: capPerFeed);
}

/// Pulls down anything the backend worker has rendered for this user's
/// subscribed feeds: refreshes local feed metadata, then downloads and
/// unzips any newly-`ready` or newly-re-rendered articles this device
/// doesn't already have the latest copy of.
///
/// This is deliberately lightweight (a Postgres query + a few file
/// downloads) — no rendering happens on-device, which is the whole reason
/// the cloud pipeline exists in the first place. Safe to call from a
/// background fetch callback under OS time limits.
class SyncService {
  const SyncService(
    this.db, {
    this.fetchReadyArticles = _defaultFetchReadyArticles,
    this.downloadArticleZip = _defaultDownloadArticleZip,
    this.recordLastSynced = _defaultRecordLastSynced,
    this.applyRetentionPolicy = _defaultApplyRetentionPolicy,
  });

  final AppDatabase db;
  final Future<List<Map<String, dynamic>>> Function({String? since}) fetchReadyArticles;
  final Future<Uint8List> Function(String storagePath) downloadArticleZip;
  final Future<void> Function(DateTime time) recordLastSynced;
  final Future<void> Function(AppDatabase db) applyRetentionPolicy;

  Future<void> syncNow() async {
    final userId = AppSupabase.client.auth.currentUser?.id;
    if (userId == null) return;

    final hasNewSubscription = await _syncFeeds(userId);
    final pendingFullFetch = await hasPendingFullFetch(db);
    // A newly-subscribed feed's already-rendered back catalog predates the
    // current watermark (this is a *shared* rendering cache — a feed's
    // articles can have been rendered long before this user subscribed),
    // so a plain `.gt('rendered_at', since)` pass would permanently skip
    // them. Fall back to a full fetch when either a subscription made on
    // another device just showed up here for the first time
    // (hasNewSubscription — caught by comparing against local feed rows),
    // or this device itself just (re)subscribed via FeedRepository.subscribe
    // (pendingFullFetch — that write happens before local feed rows can be
    // compared, so hasNewSubscription alone never catches it). The old rows
    // either pass has to re-examine all hit ArticleSyncAction.skip cheaply,
    // so this is just a network-cost trade-off, not a correctness one.
    await syncArticles(forceFullFetch: hasNewSubscription || pendingFullFetch);

    // Only clear once the full fetch above has actually completed — if it
    // threw, this line is never reached, so the signal survives for the
    // next pass to retry rather than being silently lost.
    if (pendingFullFetch) await clearPendingFullFetch(db);
  }

  /// Returns true if any feed in the response wasn't already present
  /// locally (a new subscription this pass), so [syncNow] can decide
  /// whether the article watermark is still safe to trust.
  Future<bool> _syncFeeds(String userId) async {
    final rows = await AppSupabase.client
        .from('user_feed_subscriptions')
        .select('feeds(id, url, title)')
        .eq('user_id', userId);

    final existingIds = (await db.select(db.localFeeds).get()).map((f) => f.id).toSet();
    var hasNewSubscription = false;

    for (final row in rows as List) {
      final feed = row['feeds'] as Map<String, dynamic>;
      final feedId = feed['id'] as String;
      if (!existingIds.contains(feedId)) hasNewSubscription = true;
      await db.into(db.localFeeds).insertOnConflictUpdate(
            LocalFeedsCompanion.insert(
              id: feedId,
              url: feed['url'] as String,
              title: Value(feed['title'] as String?),
            ),
          );
    }
    return hasNewSubscription;
  }

  /// Fetches and applies newly-`ready`/newly-re-rendered articles. Public
  /// (rather than the `_syncFeeds`-style private convention) so it's
  /// directly callable from tests without also exercising `_syncFeeds`'s
  /// live Supabase call — see `sync_service_test.dart`.
  ///
  /// [forceFullFetch] ignores the stored watermark for this pass (still
  /// updating it from whatever's fetched) — see the call site in
  /// [syncNow] for why a new feed subscription requires this.
  Future<void> syncArticles({bool forceFullFetch = false}) async {
    final watermarkRow = forceFullFetch
        ? null
        : await (db.select(db.syncState)..where((s) => s.id.equals(0))).getSingleOrNull();
    final since = watermarkRow?.articlesRenderedThrough;

    final rawRows = await fetchReadyArticles(since: since);
    final rows = rawRows.map(RemoteArticleRow.fromRow).toList();

    // Newest rendered_at observed this pass — becomes the new watermark,
    // but only once every row below has been handled without throwing.
    // Each row's I/O is isolated (a bad zip/network/disk failure on one
    // article doesn't stop the rest of the batch from syncing), but if
    // *any* row failed, the watermark must still NOT advance: the next
    // pass re-fetches the same `since` window and retries. That's safe and
    // cheap, since already-handled rows in that window will just hit
    // ArticleSyncAction.skip again on retry — don't "optimize" this into
    // per-row watermark advancement, or a failed row's rendered_at could
    // fall below the new watermark and be permanently skipped.
    String? newWatermark = since;
    var failureCount = 0;

    for (final remote in rows) {
      final local = await (db.select(db.localArticles)..where((a) => a.id.equals(remote.id)))
          .getSingleOrNull();

      try {
        switch (decideArticleSyncAction(remote: remote, local: local)) {
          case ArticleSyncAction.skip:
            break;
          case ArticleSyncAction.backfillRenderedAt:
            await (db.update(db.localArticles)..where((a) => a.id.equals(remote.id)))
                .write(LocalArticlesCompanion(renderedAt: Value(remote.renderedAt)));
          case ArticleSyncAction.insertPaywalled:
            await _insertPaywalledArticle(remote);
          case ArticleSyncAction.download:
            await _downloadAndStore(remote);
        }
      } catch (e) {
        log('Failed to sync article ${remote.id}: $e', name: 'SyncService');
        failureCount++;
        continue;
      }

      final rowRenderedAt = remote.renderedAt;
      if (rowRenderedAt != null &&
          (newWatermark == null || DateTime.parse(rowRenderedAt).isAfter(DateTime.parse(newWatermark)))) {
        newWatermark = rowRenderedAt;
      }
    }

    if (failureCount == 0 && newWatermark != since) {
      // id must be explicit: SQLite's INTEGER PRIMARY KEY rowid-alias
      // behavior auto-assigns a new rowid whenever the column is omitted
      // from an INSERT, ignoring the column's SQL-level DEFAULT — so
      // omitting id here would silently insert a new row every sync pass
      // instead of upserting the singleton row this table reads (id=0).
      await db.into(db.syncState).insertOnConflictUpdate(
            SyncStateCompanion.insert(id: const Value(0), articlesRenderedThrough: Value(newWatermark)),
          );
    }

    // Recorded regardless of failureCount — a partially-failed pass still
    // "ran" (see the last-synced-time UI on the Settings screen), and this
    // must happen before the throw below so it's not skipped when rows fail.
    await recordLastSynced(DateTime.now());

    // Independent bookkeeping over existing local state, not tied to this
    // pass's own success — runs on every pass (manual and background).
    await applyRetentionPolicy(db);

    // Every row was attempted (isolation above), but callers still need to
    // know something went wrong: FeedListScreen's sync-button handler shows
    // this via a SnackBar, and the WorkManager background task uses it to
    // retry sooner with backoff instead of waiting the full 15-minute
    // periodic interval. Raised after the loop (and after any watermark
    // write) so it never short-circuits processing or persistence of the
    // rows that did succeed.
    if (failureCount > 0) {
      throw StateError('$failureCount article(s) failed to sync; will retry next pass');
    }
  }

  Future<void> _insertPaywalledArticle(RemoteArticleRow article) async {
    await db.into(db.localArticles).insertOnConflictUpdate(
          LocalArticlesCompanion.insert(
            id: article.id,
            feedId: article.feedId,
            title: article.title ?? '(untitled)',
            byline: Value(article.byline),
            publishedAt: Value(_parseTimestamp(article.publishedAt)),
            downloadedAt: DateTime.now(),
            summary: Value(article.summary),
            renderedAt: Value(article.renderedAt),
          ),
        );
  }

  Future<void> _downloadAndStore(RemoteArticleRow article) async {
    final id = article.id;
    final bytes = await downloadArticleZip(article.storagePath!);

    final docsDir = await getApplicationDocumentsDirectory();
    final articleDir = Directory(p.join(docsDir.path, 'articles', id));

    // Unzip into a staging dir first, leaving any existing (working) render
    // in `articleDir` untouched until the new one is fully extracted. A
    // corrupt/truncated zip then throws without deleting a previously-good
    // article — it just leaves this pass's staging dir to be overwritten by
    // the next attempt, instead of the reader opening to an empty folder.
    final stagingDir = Directory(p.join(docsDir.path, 'articles', '$id.staging'));
    if (await stagingDir.exists()) await stagingDir.delete(recursive: true);
    await stagingDir.create(recursive: true);
    await _unzipInto(bytes, stagingDir);

    // Only now, with the new render fully on disk, swap it in. Clear out a
    // previous render's files first so a re-render with fewer images than
    // the old one doesn't leave orphaned stale files.
    if (await articleDir.exists()) await articleDir.delete(recursive: true);
    await stagingDir.rename(articleDir.path);

    await db.into(db.localArticles).insertOnConflictUpdate(
          LocalArticlesCompanion.insert(
            id: id,
            feedId: article.feedId,
            title: article.title ?? '(untitled)',
            byline: Value(article.byline),
            publishedAt: Value(_parseTimestamp(article.publishedAt)),
            downloadedAt: DateTime.now(),
            localPath: Value(p.join('articles', id)),
            renderedAt: Value(article.renderedAt),
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
