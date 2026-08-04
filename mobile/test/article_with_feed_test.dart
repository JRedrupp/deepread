import 'package:deepread/data/local/article_with_feed.dart';
import 'package:deepread/data/local/database.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('joins each article with its feed\'s title', () async {
    await db.into(db.localFeeds).insert(
          LocalFeedsCompanion.insert(
            id: 'feed-1',
            url: 'https://example.com/feed',
            title: const Value('The Verge'),
          ),
        );
    await db.into(db.localArticles).insert(
          LocalArticlesCompanion.insert(
            id: 'article-1',
            feedId: 'feed-1',
            title: 'Some article',
            downloadedAt: DateTime.now(),
          ),
        );

    final rows = await db.watchAllArticlesWithFeed().first;

    expect(rows, hasLength(1));
    expect(rows.single.article.id, 'article-1');
    expect(rows.single.feedDisplayName, 'The Verge');
  });

  test('falls back to the feed url when title is null', () async {
    await db.into(db.localFeeds).insert(
          LocalFeedsCompanion.insert(id: 'feed-1', url: 'https://example.com/feed'),
        );
    await db.into(db.localArticles).insert(
          LocalArticlesCompanion.insert(
            id: 'article-1',
            feedId: 'feed-1',
            title: 'Some article',
            downloadedAt: DateTime.now(),
          ),
        );

    final rows = await db.watchAllArticlesWithFeed().first;

    expect(rows.single.feedDisplayName, 'https://example.com/feed');
  });

  test('includes articles from every feed, not just one', () async {
    await db.into(db.localFeeds).insert(
          LocalFeedsCompanion.insert(id: 'feed-1', url: 'https://example.com/a'),
        );
    await db.into(db.localFeeds).insert(
          LocalFeedsCompanion.insert(id: 'feed-2', url: 'https://example.com/b'),
        );
    await db.into(db.localArticles).insert(
          LocalArticlesCompanion.insert(id: 'a1', feedId: 'feed-1', title: 'A1', downloadedAt: DateTime.now()),
        );
    await db.into(db.localArticles).insert(
          LocalArticlesCompanion.insert(id: 'b1', feedId: 'feed-2', title: 'B1', downloadedAt: DateTime.now()),
        );

    final rows = await db.watchAllArticlesWithFeed().first;

    expect(rows.map((r) => r.article.id).toSet(), {'a1', 'b1'});
  });
}
