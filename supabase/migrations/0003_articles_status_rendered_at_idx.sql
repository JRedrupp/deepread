-- Composite index supporting SyncService's watermark query:
-- .eq('status', 'ready').gt('rendered_at', watermark) — see TODO.md and
-- mobile/lib/features/sync/sync_service.dart.
create index articles_status_rendered_at_idx on articles (status, rendered_at);
