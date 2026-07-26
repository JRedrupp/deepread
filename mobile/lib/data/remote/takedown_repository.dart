import 'supabase_client.dart';

/// Files a takedown/report request for an article (see TODO.md's legal
/// review gate — this is a mitigation, not a substitute for it). Reviewed
/// manually by whoever operates the backend; there's no in-app status view.
class TakedownRepository {
  const TakedownRepository();

  Future<void> fileReport({required String articleId, required String reason}) async {
    final client = AppSupabase.client;
    await client.from('takedown_requests').insert({
      'article_id': articleId,
      'requester_contact': client.auth.currentUser?.email ?? 'unknown',
      'reason': reason,
    });
  }
}
