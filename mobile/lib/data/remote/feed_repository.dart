import 'package:path_provider/path_provider.dart';
import 'package:postgrest/postgrest.dart';

import '../../features/feeds/local_feed_removal.dart';
import '../../features/sync/sync_service.dart' show markPendingFullFetch;
import '../local/database.dart';
import 'supabase_client.dart';

/// Handles the "paste a URL" add-feed flow: look up (or register) the
/// shared, global `feeds` row, subscribe the current user to it, and
/// write a local placeholder immediately so the UI doesn't wait on the
/// next sync pass to show the new feed.
class FeedRepository {
  const FeedRepository(this.db);

  final AppDatabase db;

  Future<void> subscribe(String url) async {
    final client = AppSupabase.client;
    final userId = client.auth.currentUser!.id;

    final feedId = await _findOrCreateFeed(url);

    try {
      await client.from('user_feed_subscriptions').insert({
        'user_id': userId,
        'feed_id': feedId,
      });
    } on PostgrestException catch (e) {
      // Unique violation (already subscribed) — not an error worth
      // surfacing to the user.
      if (e.code != '23505') rethrow;
    }

    await db.into(db.localFeeds).insertOnConflictUpdate(
          LocalFeedsCompanion.insert(id: feedId, url: url),
        );

    // This write lands before the next sync pass ever compares local feed
    // rows, so SyncService's own newly-subscribed-elsewhere detection would
    // never catch this (re)subscription — mark it explicitly instead. See
    // markPendingFullFetch's doc comment.
    await markPendingFullFetch(db);
  }

  /// Removes the current user's subscription and this device's downloaded
  /// copy of [feedId]'s articles. Never deletes the shared `feeds`/`articles`
  /// rows themselves — other users may still be subscribed.
  ///
  /// Deletes the remote subscription first, deliberately: if local cleanup
  /// ran first and the remote delete then failed, the next sync pass would
  /// still see the subscription, find no matching local feed, and silently
  /// re-download the whole feed. Remote-first makes a failure at either step
  /// safe to retry — `DELETE` on Supabase matching zero rows is a no-op, not
  /// an error, so re-running this after a local-cleanup failure just retries
  /// the local half.
  Future<void> unsubscribe(String feedId) async {
    final client = AppSupabase.client;
    final userId = client.auth.currentUser!.id;

    await client.from('user_feed_subscriptions').delete().eq('user_id', userId).eq(
          'feed_id',
          feedId,
        );

    final docsDir = await getApplicationDocumentsDirectory();
    await removeLocalFeedData(db: db, docsDir: docsDir, feedId: feedId);
  }

  Future<String> _findOrCreateFeed(String url) async {
    final client = AppSupabase.client;

    final existing = await client.from('feeds').select('id').eq('url', url).maybeSingle();
    if (existing != null) return existing['id'] as String;

    try {
      final inserted = await client.from('feeds').insert({'url': url}).select('id').single();
      return inserted['id'] as String;
    } on PostgrestException catch (e) {
      if (e.code != '23505') rethrow;
      // Lost the race with another user adding the same feed concurrently.
      final row = await client.from('feeds').select('id').eq('url', url).single();
      return row['id'] as String;
    }
  }
}
