import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
        home: FeedListScreen(db: db, feedsStream: Stream.value(const [])),
      ),
    );
    await tester.pump();

    expect(find.text('No feeds yet — add one to get started.'), findsOneWidget);
  });

  testWidgets('AppBar has a settings icon (not a standalone sign-out icon) that opens SettingsScreen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: FeedListScreen(db: db, feedsStream: Stream.value(const [])),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.logout), findsNothing);
    expect(find.byIcon(Icons.settings), findsOneWidget);

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
  });
}
