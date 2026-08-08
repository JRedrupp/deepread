import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:deepread/data/local/database.dart';
import 'package:deepread/features/articles/article_list_tile.dart';
import 'package:deepread/theme/app_theme.dart';

void main() {
  LocalArticle article() => LocalArticle(
        id: 'article-1',
        feedId: 'feed-1',
        title: 'Some article',
        downloadedAt: DateTime.now(),
        isRead: true,
        localPath: 'articles/article-1',
        evicted: false,
      );

  testWidgets('shows a bracketed feed label when feedLabel is provided', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: ArticleListTile(db: db, article: article(), feedLabel: 'The Verge'),
        ),
      ),
    );

    expect(find.text('[The Verge]'), findsOneWidget);
  });

  testWidgets('omits the feed label entirely when feedLabel is null', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: ArticleListTile(db: db, article: article()),
        ),
      ),
    );

    // article() is read, downloaded, not evicted — no NEW/SUMMARY ONLY/
    // REMOVED tags either, so no bracketed text at all should render.
    expect(find.textContaining('['), findsNothing);
  });

  testWidgets('a long feed URL badge truncates instead of overflowing the row at a narrow width',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final unreadArticle = LocalArticle(
      id: 'article-2',
      feedId: 'feed-1',
      title: 'Some article',
      downloadedAt: DateTime.now(),
      isRead: false,
      localPath: 'articles/article-2',
      evicted: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: ArticleListTile(
            db: db,
            article: unreadArticle,
            feedLabel: 'https://feeds.arstechnica.com/arstechnica/index',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
