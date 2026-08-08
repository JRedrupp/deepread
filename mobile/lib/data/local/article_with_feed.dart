import 'package:drift/drift.dart';

import 'database.dart';

/// One [LocalArticle] plus the display name of the feed it belongs to, for
/// the combined all-articles view — where the per-feed context an
/// `ArticleListScreen` gets for free (its own AppBar title) has to be
/// carried on each row instead.
typedef ArticleWithFeed = ({LocalArticle article, String feedDisplayName});

extension AllArticlesQuery on AppDatabase {
  /// Every downloaded article across every subscribed feed, joined against
  /// [LocalFeeds] for its display name (`title ?? url`, the same fallback
  /// `FeedListScreen` already uses) — a plain SQL join, not a denormalized
  /// column, so a later feed rename never needs a backfill pass.
  Stream<List<ArticleWithFeed>> watchAllArticlesWithFeed() {
    final query = select(localArticles).join([
      innerJoin(localFeeds, localFeeds.id.equalsExp(localArticles.feedId)),
    ]);
    return query.watch().map(
          (rows) => rows.map((row) {
            final article = row.readTable(localArticles);
            final feed = row.readTable(localFeeds);
            return (article: article, feedDisplayName: feed.title ?? feed.url);
          }).toList(),
        );
  }
}
