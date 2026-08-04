import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../../data/local/database.dart';
import '../../theme/app_theme.dart';
import 'article_reader_screen.dart';

/// One article's card body, shared between `ArticleListScreen` (a single
/// feed, so the feed is already implied by that screen's own AppBar title)
/// and the combined all-articles view (many feeds, so each row needs its
/// own [feedLabel] to say which one it came from).
class ArticleListTile extends StatelessWidget {
  const ArticleListTile({super.key, required this.db, required this.article, this.feedLabel});

  final AppDatabase db;
  final LocalArticle article;

  /// Feed display name to show ahead of the status tags, or null to omit
  /// it (the per-feed screen doesn't need it).
  final String? feedLabel;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryColor = isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary;

    return Card(
      child: ListTile(
        title: Text(article.title),
        subtitle: Row(
          children: [
            if (feedLabel != null)
              Flexible(
                child: StatusTag(
                  feedLabel!,
                  color: secondaryColor,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (feedLabel != null) const SizedBox(width: 8),
            if (!article.isRead) const StatusTag('NEW'),
            if (!article.isRead) const SizedBox(width: 8),
            if (article.localPath == null) StatusTag(article.evicted ? 'REMOVED' : 'SUMMARY ONLY'),
            if (article.localPath == null) const SizedBox(width: 8),
            Text(
              article.publishedAt?.toIso8601String().split('T').first ?? '',
              style: AppTheme.metadataStyle(context),
            ),
          ],
        ),
        onTap: () async {
          await (db.update(db.localArticles)..where((a) => a.id.equals(article.id)))
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
  }
}
