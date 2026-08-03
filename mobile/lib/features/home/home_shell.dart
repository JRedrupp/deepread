import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/local/article_with_feed.dart';
import '../../data/local/database.dart';
import '../../data/remote/feed_repository.dart';
import '../../data/remote/supabase_client.dart';
import '../../theme/app_theme.dart';
import '../articles/all_articles_screen.dart';
import '../articles/article_sort_order.dart';
import '../auth/local_data_reset.dart';
import '../feeds/add_feed_screen.dart';
import '../feeds/feed_list_screen.dart';
import '../settings/settings_screen.dart';
import '../sync/sync_service.dart';

/// The app's home screen: a shared AppBar (sync + settings, plus
/// filter/sort when the All Articles tab is active) and a bottom nav bar
/// switching between the Feeds tab ([FeedListScreen]) and the combined
/// All Articles tab ([AllArticlesScreen]). Owns state that's really
/// app-global rather than per-tab — sync-in-progress, sign-out, and
/// unsubscribe-execution — since all of it used to live on
/// [FeedListScreen] back when it was the app's only home screen.
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.db,
    this.feedsStream,
    this.articlesStream,
    this.onUnsubscribe,
  });

  final AppDatabase db;
  final Stream<List<LocalFeed>>? feedsStream;
  final Stream<List<ArticleWithFeed>>? articlesStream;

  /// Overridable so widget tests can assert an unsubscribe was requested
  /// for the right feed without touching `FeedRepository`/Supabase. When
  /// null (the real app), [_unsubscribeFeed] is used.
  final Future<void> Function(LocalFeed feed)? onUnsubscribe;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selectedIndex = 0;
  bool _syncing = false;
  Future<void>? _syncFuture;
  bool _unreadOnly = false;
  ArticleSortOrder _sortOrder = ArticleSortOrder.newestFirst;

  @override
  void initState() {
    super.initState();
    unawaited(_syncNow());
  }

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

  Future<void> _addFeed(String url) async {
    await FeedRepository(widget.db).subscribe(url);
    // Pull immediately rather than waiting for the next periodic
    // background sync, so the feed's title (and any already-rendered
    // articles) show up right away.
    unawaited(_syncNow());
  }

  Future<void> _unsubscribeFeed(LocalFeed feed) async {
    try {
      // Drain any in-flight sync first — a sync mid-flight could
      // re-insert this feed's rows between local cleanup and its own
      // completion.
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

  @override
  Widget build(BuildContext context) {
    final isAllArticles = _selectedIndex == 1;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryColor = isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('DeepRead'),
        actions: [
          if (isAllArticles) ...[
            IconButton(
              icon: Icon(_unreadOnly ? Icons.filter_alt : Icons.filter_alt_outlined),
              tooltip: _unreadOnly ? 'Showing unread only' : 'Show all',
              onPressed: () => setState(() => _unreadOnly = !_unreadOnly),
            ),
            PopupMenuButton<ArticleSortOrder>(
              icon: const Icon(Icons.sort),
              tooltip: 'Sort',
              initialValue: _sortOrder,
              onSelected: (order) => setState(() => _sortOrder = order),
              itemBuilder: (context) => const [
                PopupMenuItem(value: ArticleSortOrder.newestFirst, child: Text('Newest first')),
                PopupMenuItem(value: ArticleSortOrder.oldestFirst, child: Text('Oldest first')),
              ],
            ),
          ],
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
                builder: (_) => SettingsScreen(onSignOut: _signOut, db: widget.db),
              ),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          FeedListScreen(
            db: widget.db,
            feedsStream: widget.feedsStream,
            onUnsubscribe: widget.onUnsubscribe ?? _unsubscribeFeed,
          ),
          AllArticlesScreen(
            db: widget.db,
            unreadOnly: _unreadOnly,
            sortOrder: _sortOrder,
            articlesStream: widget.articlesStream,
          ),
        ],
      ),
      floatingActionButton: _selectedIndex == 0
          ? FloatingActionButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AddFeedScreen(onSubmit: _addFeed),
                ),
              ),
              child: const Icon(Icons.add),
            )
          : null,
      bottomNavigationBar: DecoratedBox(
        // Flat, bordered look (matching the app's card language) instead
        // of Material 3's default pill-indicator NavigationBar.
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: Theme.of(context).dividerTheme.color ?? secondaryColor)),
        ),
        child: NavigationBarTheme(
          data: NavigationBarThemeData(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            indicatorColor: Colors.transparent,
            labelTextStyle: WidgetStateProperty.resolveWith(
              (states) => TextStyle(
                fontSize: 12,
                color: states.contains(WidgetState.selected) ? AppTheme.accent : secondaryColor,
                fontWeight: states.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          child: NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) => setState(() => _selectedIndex = index),
            destinations: [
              NavigationDestination(
                icon: Icon(Icons.rss_feed, color: secondaryColor),
                selectedIcon: const Icon(Icons.rss_feed, color: AppTheme.accent),
                label: 'Feeds',
              ),
              NavigationDestination(
                icon: Icon(Icons.dynamic_feed, color: secondaryColor),
                selectedIcon: const Icon(Icons.dynamic_feed, color: AppTheme.accent),
                label: 'All Articles',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
