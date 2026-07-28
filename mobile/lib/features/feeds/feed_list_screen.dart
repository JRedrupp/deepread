import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/local/database.dart';
import '../../data/remote/feed_repository.dart';
import '../../data/remote/supabase_client.dart';
import '../articles/article_list_screen.dart';
import '../auth/local_data_reset.dart';
import '../settings/settings_screen.dart';
import '../sync/sync_service.dart';
import 'add_feed_screen.dart';

class FeedListScreen extends StatefulWidget {
  const FeedListScreen({super.key, required this.db, this.feedsStream, this.onUnsubscribe});

  final AppDatabase db;

  /// Overridable so widget tests can supply a plain [Stream] instead of a
  /// live drift query — drift's reactive query streams don't reliably
  /// deliver events when subscribed to directly inside a testWidgets
  /// fake-async zone.
  final Stream<List<LocalFeed>>? feedsStream;

  /// Overridable so widget tests can assert an unsubscribe was requested
  /// for the right feed without touching `AppSupabase.client` or
  /// `path_provider` (both hit by the default `_removeFeed`).
  final Future<void> Function(LocalFeed feed)? onUnsubscribe;

  @override
  State<FeedListScreen> createState() => _FeedListScreenState();
}

class _FeedListScreenState extends State<FeedListScreen> {
  late final Stream<List<LocalFeed>> _feedsStream;

  @override
  void initState() {
    super.initState();
    // Built once here, not in `build`, so a parent rebuild doesn't hand
    // StreamBuilder a new Stream identity (which would tear down and
    // resubscribe the underlying drift query on every rebuild).
    _feedsStream = widget.feedsStream ?? widget.db.select(widget.db.localFeeds).watch();
    unawaited(_syncNow());
  }

  bool _syncing = false;
  Future<void>? _syncFuture;

  Future<void> _syncNow() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    final future = SyncService(widget.db).syncNow();
    _syncFuture = future;
    try {
      await future;
    } catch (e) {
      // Sync failures (offline, expired session, Supabase unreachable)
      // shouldn't crash the screen — the user can already see and read
      // whatever was downloaded previously.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _signOut() async {
    final db = widget.db; // capture before any await — this widget may be
    // disposed once AuthGate reacts to the `signedOut` auth event.

    try {
      // signOut() fires the `signedOut` event (and AuthGate's navigation
      // to LoginScreen) essentially synchronously with the local session
      // removal, before its best-effort server-side token revoke. Swallow
      // failures here (e.g. offline revoke) — they must not block the
      // local wipe below.
      await AppSupabase.client.auth.signOut();
    } catch (_) {}

    // Drain any sync already in flight (the app-open sync from initState,
    // or one launched by _addFeed) before wiping — syncNow() only checks
    // currentUser once at its start, so signOut() above prevents *new*
    // syncs but can't stop one already past that check. It will likely
    // start throwing (401s) once the token's gone — irrelevant, swallowed.
    try {
      await _syncFuture;
    } catch (_) {}

    final docsDir = await getApplicationDocumentsDirectory();
    await resetLocalData(
      db: db,
      articlesDir: Directory(p.join(docsDir.path, 'articles')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DeepRead'),
        actions: [
          IconButton(
            icon: _syncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            tooltip: 'Sync now',
            onPressed: _syncing ? null : _syncNow,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SettingsScreen(onSignOut: _signOut),
              ),
            ),
          ),
        ],
      ),
      body: StreamBuilder<List<LocalFeed>>(
        stream: _feedsStream,
        builder: (context, snapshot) {
          final feeds = snapshot.data ?? const [];
          if (feeds.isEmpty) {
            return const Center(child: Text('No feeds yet — add one to get started.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: feeds.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final feed = feeds[index];
              return Card(
                child: ListTile(
                  title: Text(feed.title ?? feed.url),
                  subtitle: Text(feed.url, style: Theme.of(context).textTheme.bodySmall),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ArticleListScreen(db: widget.db, feed: feed),
                    ),
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (_) => _confirmUnsubscribe(feed),
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'unsubscribe', child: Text('Unsubscribe')),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AddFeedScreen(onSubmit: _addFeed),
          ),
        ),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _addFeed(String url) async {
    await FeedRepository(widget.db).subscribe(url);
    // Pull immediately rather than waiting for the next periodic
    // background sync, so the feed's title (and any already-rendered
    // articles) show up right away.
    unawaited(_syncNow());
  }

  Future<void> _confirmUnsubscribe(LocalFeed feed) async {
    final articleCount = (await (widget.db.select(widget.db.localArticles)
              ..where((a) => a.feedId.equals(feed.id)))
            .get())
        .length;

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsubscribe from feed?'),
        content: Text(
          'This removes $articleCount downloaded article${articleCount == 1 ? '' : 's'} '
          'from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Unsubscribe'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await (widget.onUnsubscribe ?? _removeFeed)(feed);
    }
  }

  Future<void> _removeFeed(LocalFeed feed) async {
    try {
      // Drain any in-flight sync first — same race _signOut guards
      // against: a sync mid-flight could re-insert this feed's rows
      // between our local cleanup and its own completion.
      await _syncFuture;
    } catch (_) {}

    try {
      await FeedRepository(widget.db).unsubscribe(feed.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove feed: $e')),
        );
      }
    }
  }
}
