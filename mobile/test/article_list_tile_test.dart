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
}
