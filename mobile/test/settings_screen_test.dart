import 'package:deepread/features/settings/settings_repository.dart';
import 'package:deepread/features/settings/settings_screen.dart';
import 'package:deepread/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('formatLastSynced', () {
    test('returns Never for null', () {
      expect(formatLastSynced(null), 'Never');
    });

    test('formats a local time in a fixed, zero-padded format', () {
      // Constructed as local (no .utc) so the .toLocal() inside
      // formatLastSynced is a no-op — deterministic regardless of the
      // machine running the test.
      expect(formatLastSynced(DateTime(2026, 7, 28, 9, 5)), '2026-07-28 09:05');
    });
  });

  group('SettingsScreen', () {
    testWidgets('shows Never when nothing has synced yet', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsRepository(await SharedPreferences.getInstance());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: SettingsScreen(onSignOut: () async {}, settingsRepository: settings),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Never'), findsOneWidget);
    });

    testWidgets('shows the persisted last-synced time', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsRepository(await SharedPreferences.getInstance());
      await settings.setLastSyncedAt(DateTime(2026, 7, 28, 9, 5));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: SettingsScreen(onSignOut: () async {}, settingsRepository: settings),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('2026-07-28 09:05'), findsOneWidget);
    });

    testWidgets('tapping Sign out invokes the callback and pops back to the previous route', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsRepository(await SharedPreferences.getInstance());
      var signOutCalls = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SettingsScreen(
                        onSignOut: () async {
                          signOutCalls++;
                        },
                        settingsRepository: settings,
                      ),
                    ),
                  ),
                  child: const Text('open settings'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open settings'));
      await tester.pumpAndSettle();
      expect(find.text('Sign out'), findsOneWidget);

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();

      expect(signOutCalls, 1);
      expect(find.text('open settings'), findsOneWidget);
      expect(find.text('Sign out'), findsNothing);
    });
  });
}
