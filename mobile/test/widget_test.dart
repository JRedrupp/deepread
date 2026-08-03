import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:deepread/data/local/database.dart';
import 'package:deepread/features/feeds/feed_list_screen.dart';
import 'package:deepread/theme/app_theme.dart';

void main() {
  testWidgets('Feed list shows empty state with no feeds', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: FeedListScreen(
          db: db,
          feedsStream: Stream.value(const []),
          onUnsubscribe: (_) async {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('No feeds yet — add one to get started.'), findsOneWidget);
  });
}
