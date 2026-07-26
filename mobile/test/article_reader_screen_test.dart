import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:deepread/data/local/database.dart';
import 'package:deepread/features/articles/article_reader_screen.dart';
import 'package:deepread/theme/app_theme.dart';

void main() {
  testWidgets('shows the RSS summary instead of a WebView for a paywalled article', (tester) async {
    final article = LocalArticle(
      id: 'article-1',
      feedId: 'feed-1',
      title: 'Paywalled article',
      downloadedAt: DateTime.now(),
      summary: 'An RSS-provided summary.',
      isRead: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: ArticleReaderScreen(article: article),
      ),
    );
    await tester.pump();

    expect(find.text('An RSS-provided summary.'), findsOneWidget);
    expect(find.byType(WebViewWidget), findsNothing);
  });
}
