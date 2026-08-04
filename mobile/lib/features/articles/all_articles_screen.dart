import 'package:flutter/material.dart';

import '../../data/local/article_with_feed.dart';
import '../../data/local/database.dart';
import 'article_list_tile.dart';
import 'article_sort_order.dart';

/// Body-only widget (no own AppBar/Scaffold) embedded in `HomeShell`'s
/// bottom-nav shell. Sort/filter state is owned by `HomeShell`, not here,
/// since the icons that control it live in the shell's shared AppBar.
class AllArticlesScreen extends StatefulWidget {
  const AllArticlesScreen({
    super.key,
    required this.db,
    required this.unreadOnly,
    required this.sortOrder,
    this.articlesStream,
  });

  final AppDatabase db;
  final bool unreadOnly;
  final ArticleSortOrder sortOrder;

  /// Overridable so widget tests can supply a plain [Stream] instead of a
  /// live drift query — see TECH_DEBT.md's note on drift .watch() streams
  /// inside testWidgets fake-async zones.
  final Stream<List<ArticleWithFeed>>? articlesStream;

  @override
  State<AllArticlesScreen> createState() => _AllArticlesScreenState();
}

class _AllArticlesScreenState extends State<AllArticlesScreen> {
  late final Stream<List<ArticleWithFeed>> _articlesStream;

  @override
  void initState() {
    super.initState();
    _articlesStream = widget.articlesStream ?? widget.db.watchAllArticlesWithFeed();
  }

  List<ArticleWithFeed> _applySortAndFilter(List<ArticleWithFeed> rows) {
    var result = widget.unreadOnly ? rows.where((r) => !r.article.isRead).toList() : List.of(rows);
    result.sort((a, b) {
      final aDate = a.article.publishedAt ?? a.article.downloadedAt;
      final bDate = b.article.publishedAt ?? b.article.downloadedAt;
      return widget.sortOrder == ArticleSortOrder.newestFirst
          ? bDate.compareTo(aDate)
          : aDate.compareTo(bDate);
    });
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ArticleWithFeed>>(
      stream: _articlesStream,
      builder: (context, snapshot) {
        final rows = _applySortAndFilter(snapshot.data ?? const []);
        if (rows.isEmpty) {
          return Center(
            child: Text(
              widget.unreadOnly ? 'No unread articles.' : 'No articles downloaded yet.',
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: rows.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final row = rows[index];
            return ArticleListTile(db: widget.db, article: row.article, feedLabel: row.feedDisplayName);
          },
        );
      },
    );
  }
}
