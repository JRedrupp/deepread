import 'dart:io';

import 'package:deepread/data/local/database.dart';
import 'package:deepread/features/feeds/local_feed_removal.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late AppDatabase db;
  late Directory docsDir;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    docsDir = await Directory.systemTemp.createTemp('deepread_test_');
  });

  tearDown(() async {
    await db.close();
    if (await docsDir.exists()) {
      await docsDir.delete(recursive: true);
    }
  });

  Future<void> seedFeed(String feedId, String url) async {
    await db.into(db.localFeeds).insert(
          LocalFeedsCompanion.insert(id: feedId, url: url),
        );
  }

  Future<void> seedArticle(
    String articleId,
    String feedId, {
    String? localPath,
  }) async {
    await db.into(db.localArticles).insert(
          LocalArticlesCompanion.insert(
            id: articleId,
            feedId: feedId,
            title: 'Article $articleId',
            downloadedAt: DateTime.now(),
            localPath: Value(localPath),
          ),
        );
  }

  Future<void> writeArticleDir(String relativePath) async {
    final dir = Directory(p.join(docsDir.path, relativePath));
    await dir.create(recursive: true);
    await File(p.join(dir.path, 'index.html')).writeAsString('<html></html>');
  }

  test('removes the target feed\'s rows and article directory, leaving other feeds untouched', () async {
    await seedFeed('feed-1', 'https://example.com/feed-1');
    await seedFeed('feed-2', 'https://example.com/feed-2');
    await seedArticle('article-1', 'feed-1', localPath: 'articles/article-1');
    await seedArticle('article-2', 'feed-2', localPath: 'articles/article-2');
    await writeArticleDir('articles/article-1');
    await writeArticleDir('articles/article-2');

    await removeLocalFeedData(db: db, docsDir: docsDir, feedId: 'feed-1');

    final feeds = await db.select(db.localFeeds).get();
    expect(feeds.map((f) => f.id), ['feed-2']);

    final articles = await db.select(db.localArticles).get();
    expect(articles.map((a) => a.id), ['article-2']);

    expect(await Directory(p.join(docsDir.path, 'articles/article-1')).exists(), isFalse);
    expect(await Directory(p.join(docsDir.path, 'articles/article-2')).exists(), isTrue);
  });

  test('skips articles with a null localPath without throwing', () async {
    await seedFeed('feed-1', 'https://example.com/feed-1');
    await seedArticle('article-1', 'feed-1'); // paywalled — no localPath

    await removeLocalFeedData(db: db, docsDir: docsDir, feedId: 'feed-1');

    expect(await db.select(db.localFeeds).get(), isEmpty);
    expect(await db.select(db.localArticles).get(), isEmpty);
  });

  test('no-ops cleanly when the article directory is already missing', () async {
    await seedFeed('feed-1', 'https://example.com/feed-1');
    await seedArticle('article-1', 'feed-1', localPath: 'articles/article-1');
    // Deliberately never create the directory on disk.

    await removeLocalFeedData(db: db, docsDir: docsDir, feedId: 'feed-1');

    expect(await db.select(db.localFeeds).get(), isEmpty);
    expect(await db.select(db.localArticles).get(), isEmpty);
  });

  test('no-ops cleanly when feedId has no local rows at all', () async {
    await seedFeed('feed-2', 'https://example.com/feed-2');

    await removeLocalFeedData(db: db, docsDir: docsDir, feedId: 'feed-does-not-exist');

    final feeds = await db.select(db.localFeeds).get();
    expect(feeds.map((f) => f.id), ['feed-2']);
  });
}
