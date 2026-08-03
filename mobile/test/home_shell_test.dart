import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:deepread/data/local/database.dart';
import 'package:deepread/features/home/home_shell.dart';
import 'package:deepread/theme/app_theme.dart';

void main() {
  Future<void> pumpShell(
    WidgetTester tester, {
    List<LocalFeed> feeds = const [],
  }) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    // The Settings screen's list is taller than the default test viewport —
    // use a tall viewport so "Sign out" further down the list actually
    // gets built when a test navigates there.
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: HomeShell(
          db: db,
          feedsStream: Stream.value(feeds),
          articlesStream: Stream.value(const []),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('AppBar has a settings icon (not a standalone sign-out icon) that opens SettingsScreen',
      (tester) async {
    await pumpShell(tester);

    expect(find.byIcon(Icons.logout), findsNothing);
    expect(find.byIcon(Icons.settings), findsOneWidget);

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
  });

  testWidgets('Feeds tab is selected by default, showing the add-feed FAB and no filter/sort icons',
      (tester) async {
    await pumpShell(tester);

    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(find.byIcon(Icons.filter_alt_outlined), findsNothing);
    expect(find.byIcon(Icons.sort), findsNothing);
  });

  testWidgets('switching to the All Articles tab hides the FAB and shows filter/sort icons',
      (tester) async {
    await pumpShell(tester);

    await tester.tap(find.text('All Articles'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.add), findsNothing);
    expect(find.byIcon(Icons.filter_alt_outlined), findsOneWidget);
    expect(find.byIcon(Icons.sort), findsOneWidget);
  });

  testWidgets('switching tabs preserves the Feeds tab content instead of tearing it down',
      (tester) async {
    await pumpShell(tester, feeds: [
      const LocalFeed(id: 'feed-1', url: 'https://example.com/feed', title: 'Example Feed'),
    ]);

    expect(find.text('Example Feed'), findsOneWidget);

    await tester.tap(find.text('All Articles'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Feeds'));
    await tester.pumpAndSettle();

    expect(find.text('Example Feed'), findsOneWidget);
  });
}
