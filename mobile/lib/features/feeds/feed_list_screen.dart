import 'package:flutter/material.dart';

import '../../data/local/database.dart';
import '../articles/article_list_screen.dart';

/// Body-only widget (no own Scaffold/AppBar) — the Feeds tab inside
/// `HomeShell`'s bottom-nav shell. Sync-in-progress state, the AppBar's
/// sync/settings icons, the "add feed" FAB, and unsubscribe execution all
/// moved up to `HomeShell` when this stopped being the app's own home
/// screen; this widget only renders the list and its confirmation dialog.
class FeedListScreen extends StatefulWidget {
  const FeedListScreen({super.key, required this.db, this.feedsStream, required this.onUnsubscribe});

  final AppDatabase db;

  /// Overridable so widget tests can supply a plain [Stream] instead of a
  /// live drift query — drift's reactive query streams don't reliably
  /// deliver events when subscribed to directly inside a testWidgets
  /// fake-async zone.
  final Stream<List<LocalFeed>>? feedsStream;

  /// Called once the user confirms unsubscribing from a feed. Always
  /// supplied by `HomeShell` in the real app; tests inject their own to
  /// assert on the tapped feed without touching `FeedRepository`/Supabase.
  final Future<void> Function(LocalFeed feed) onUnsubscribe;

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
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<LocalFeed>>(
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
    );
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
      await widget.onUnsubscribe(feed);
    }
  }
}
