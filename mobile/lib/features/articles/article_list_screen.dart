import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../../data/local/database.dart';
import '../../theme/app_theme.dart';
import 'article_reader_screen.dart';

enum _SortOrder { newestFirst, oldestFirst }

class ArticleListScreen extends StatefulWidget {
  const ArticleListScreen({super.key, required this.db, required this.feed, this.articlesStream});

  final AppDatabase db;
  final LocalFeed feed;

  /// Overridable so widget tests can supply a plain [Stream] instead of a
  /// live drift query — drift's reactive query streams don't reliably
  /// deliver events when subscribed to directly inside a testWidgets
  /// fake-async zone.
  final Stream<List<LocalArticle>>? articlesStream;

  @override
  State<ArticleListScreen> createState() => _ArticleListScreenState();
}

class _ArticleListScreenState extends State<ArticleListScreen> {
  late final Stream<List<LocalArticle>> _articlesStream;

  _SortOrder _sortOrder = _SortOrder.newestFirst;
  bool _unreadOnly = false;

  @override
  void initState() {
    super.initState();
    // Unsorted/unfiltered at the query level — sort and filter are applied
    // client-side in the builder below so toggling them doesn't tear down
    // and resubscribe the underlying drift stream.
    _articlesStream = widget.articlesStream ??
        (widget.db.select(widget.db.localArticles)..where((a) => a.feedId.equals(widget.feed.id))).watch();
  }

  List<LocalArticle> _applySortAndFilter(List<LocalArticle> articles) {
    var result = _unreadOnly ? articles.where((a) => !a.isRead).toList() : List.of(articles);
    result.sort((a, b) {
      final aDate = a.publishedAt ?? a.downloadedAt;
      final bDate = b.publishedAt ?? b.downloadedAt;
      return _sortOrder == _SortOrder.newestFirst
          ? bDate.compareTo(aDate)
          : aDate.compareTo(bDate);
    });
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.feed.title ?? widget.feed.url),
        actions: [
          IconButton(
            icon: Icon(_unreadOnly ? Icons.filter_alt : Icons.filter_alt_outlined),
            tooltip: _unreadOnly ? 'Showing unread only' : 'Show all',
            onPressed: () => setState(() => _unreadOnly = !_unreadOnly),
          ),
          PopupMenuButton<_SortOrder>(
            icon: const Icon(Icons.sort),
            tooltip: 'Sort',
            initialValue: _sortOrder,
            onSelected: (order) => setState(() => _sortOrder = order),
            itemBuilder: (context) => const [
              PopupMenuItem(value: _SortOrder.newestFirst, child: Text('Newest first')),
              PopupMenuItem(value: _SortOrder.oldestFirst, child: Text('Oldest first')),
            ],
          ),
        ],
      ),
      body: StreamBuilder<List<LocalArticle>>(
        stream: _articlesStream,
        builder: (context, snapshot) {
          final articles = _applySortAndFilter(snapshot.data ?? const []);
          if (articles.isEmpty) {
            return Center(
              child: Text(
                _unreadOnly ? 'No unread articles.' : 'No articles downloaded yet.',
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: articles.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final article = articles[index];
              return Card(
                child: ListTile(
                  title: Text(article.title),
                  subtitle: Row(
                    children: [
                      if (!article.isRead) const StatusTag('NEW'),
                      if (!article.isRead) const SizedBox(width: 8),
                      if (article.localPath == null) const StatusTag('SUMMARY ONLY'),
                      if (article.localPath == null) const SizedBox(width: 8),
                      Text(
                        article.publishedAt?.toIso8601String().split('T').first ?? '',
                        style: AppTheme.metadataStyle(context),
                      ),
                    ],
                  ),
                  onTap: () async {
                    await (widget.db.update(widget.db.localArticles)
                          ..where((a) => a.id.equals(article.id)))
                        .write(const LocalArticlesCompanion(isRead: Value(true)));
                    if (context.mounted) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ArticleReaderScreen(article: article),
                        ),
                      );
                    }
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
