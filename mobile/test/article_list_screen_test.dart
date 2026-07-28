import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:deepread/data/local/database.dart';
import 'package:deepread/features/articles/article_list_screen.dart';
import 'package:deepread/theme/app_theme.dart';

void main() {
  testWidgets('shows a SUMMARY ONLY tag for a paywalled article', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    const feed = LocalFeed(id: 'feed-1', url: 'https://example.com/feed', title: null);
    final paywalled = LocalArticle(
      id: 'article-1',
      feedId: 'feed-1',
      title: 'Paywalled article',
      downloadedAt: DateTime.now(),
      summary: 'A summary.',
      isRead: false,
      evicted: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: ArticleListScreen(
          db: db,
          feed: feed,
          articlesStream: Stream.value([paywalled]),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('[SUMMARY ONLY]'), findsOneWidget);
  });

  testWidgets('shows a REMOVED tag (not SUMMARY ONLY) for an evicted article', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    const feed = LocalFeed(id: 'feed-1', url: 'https://example.com/feed', title: null);
    final evicted = LocalArticle(
      id: 'article-1',
      feedId: 'feed-1',
      title: 'Previously downloaded article',
      downloadedAt: DateTime.now(),
      isRead: true,
      evicted: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: ArticleListScreen(
          db: db,
          feed: feed,
          articlesStream: Stream.value([evicted]),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('[REMOVED]'), findsOneWidget);
    expect(find.text('[SUMMARY ONLY]'), findsNothing);
  });
}
