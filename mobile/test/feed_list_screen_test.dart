import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:deepread/data/local/database.dart';
import 'package:deepread/features/feeds/feed_list_screen.dart';
import 'package:deepread/theme/app_theme.dart';

void main() {
  const feed = LocalFeed(id: 'feed-1', url: 'https://example.com/feed', title: 'Example Feed');

  Future<void> pumpScreen(
    WidgetTester tester, {
    required Future<void> Function(LocalFeed feed) onUnsubscribe,
  }) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: FeedListScreen(
          db: db,
          feedsStream: Stream.value([feed]),
          onUnsubscribe: onUnsubscribe,
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('selecting Unsubscribe from the menu shows a confirmation dialog', (tester) async {
    await pumpScreen(tester, onUnsubscribe: (_) async {});

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unsubscribe'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('cancelling the confirmation dialog does not call onUnsubscribe', (tester) async {
    var called = false;
    await pumpScreen(tester, onUnsubscribe: (_) async => called = true);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unsubscribe'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(called, isFalse);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('confirming the dialog calls onUnsubscribe with the tapped feed', (tester) async {
    LocalFeed? removedFeed;
    await pumpScreen(tester, onUnsubscribe: (feed) async => removedFeed = feed);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unsubscribe'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unsubscribe').last);
    await tester.pumpAndSettle();

    expect(removedFeed?.id, 'feed-1');
    expect(find.byType(AlertDialog), findsNothing);
  });
}
