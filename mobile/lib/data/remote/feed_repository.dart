import 'package:postgrest/postgrest.dart';

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
