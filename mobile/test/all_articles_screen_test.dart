import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:deepread/data/local/article_with_feed.dart';
import 'package:deepread/data/local/database.dart';
import 'package:deepread/features/articles/all_articles_screen.dart';
import 'package:deepread/features/articles/article_sort_order.dart';
import 'package:deepread/theme/app_theme.dart';

void main() {
  LocalArticle article({
    required String id,
    required bool isRead,
    required DateTime publishedAt,
  }) =>
      LocalArticle(
        id: id,
        feedId: 'feed-1',
        title: 'Article $id',
        downloadedAt: publishedAt,
        publishedAt: publishedAt,
        isRead: isRead,
        localPath: 'articles/$id',
        evicted: false,
      );

  Future<void> pumpScreen(
    WidgetTester tester, {
    required List<ArticleWithFeed> rows,
    bool unreadOnly = false,
    ArticleSortOrder sortOrder = ArticleSortOrder.newestFirst,
  }) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: AllArticlesScreen(
          db: db,
          unreadOnly: unreadOnly,
          sortOrder: sortOrder,
          articlesStream: Stream.value(rows),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows each article tagged with its own feed name', (tester) async {
    await pumpScreen(tester, rows: [
      (article: article(id: 'a', isRead: true, publishedAt: DateTime(2026, 1, 1)), feedDisplayName: 'The Verge'),
      (article: article(id: 'b', isRead: true, publishedAt: DateTime(2026, 1, 2)), feedDisplayName: 'Ars Technica'),
    ]);

    expect(find.text('[The Verge]'), findsOneWidget);
    expect(find.text('[Ars Technica]'), findsOneWidget);
  });

  testWidgets('newestFirst sorts across feeds by date, not grouped by feed', (tester) async {
    await pumpScreen(
      tester,
      rows: [
        (article: article(id: 'old', isRead: true, publishedAt: DateTime(2026, 1, 1)), feedDisplayName: 'Feed A'),
        (article: article(id: 'new', isRead: true, publishedAt: DateTime(2026, 1, 5)), feedDisplayName: 'Feed B'),
      ],
      sortOrder: ArticleSortOrder.newestFirst,
    );

    final titles = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList();
    expect(titles.indexOf('Article new') < titles.indexOf('Article old'), isTrue);
  });

  testWidgets('unreadOnly filters out read articles', (tester) async {
    await pumpScreen(
      tester,
      rows: [
        (article: article(id: 'read', isRead: true, publishedAt: DateTime(2026, 1, 1)), feedDisplayName: 'Feed A'),
        (article: article(id: 'unread', isRead: false, publishedAt: DateTime(2026, 1, 2)), feedDisplayName: 'Feed A'),
      ],
      unreadOnly: true,
    );

    expect(find.text('Article unread'), findsOneWidget);
    expect(find.text('Article read'), findsNothing);
  });

  testWidgets('shows empty-state text when there are no articles', (tester) async {
    await pumpScreen(tester, rows: []);

    expect(find.text('No articles downloaded yet.'), findsOneWidget);
  });
}
