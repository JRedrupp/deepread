import 'package:deepread/features/settings/settings_repository.dart';
import 'package:deepread/features/settings/settings_screen.dart';
import 'package:deepread/theme/app_theme.dart';
import 'package:deepread/theme/theme_controller.dart';
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
    setUp(() => ThemeController.mode.value = ThemeMode.dark);

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

      // The settings list has grown taller than the test viewport (more
      // sections were added since this test was written) — scroll it into
      // view before tapping.
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();

      expect(signOutCalls, 1);
      expect(find.text('open settings'), findsOneWidget);
      expect(find.text('Sign out'), findsNothing);
    });

    testWidgets('defaults to the 15 min preset and wifi-only off', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsRepository(await SharedPreferences.getInstance());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: SettingsScreen(onSignOut: () async {}, settingsRepository: settings),
        ),
      );
      await tester.pumpAndSettle();

      final segmentedButton = tester.widget<SegmentedButton<int>>(find.byType(SegmentedButton<int>));
      expect(segmentedButton.selected, {15});
      final wifiSwitch = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(wifiSwitch.value, isFalse);
    });

    testWidgets('selecting a frequency preset persists it and re-registers background sync', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsRepository(await SharedPreferences.getInstance());
      int? registeredFrequency;
      bool? registeredWifiOnly;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: SettingsScreen(
            onSignOut: () async {},
            settingsRepository: settings,
            onSyncSettingsChanged: ({required frequencyMinutes, required wifiOnly}) async {
              registeredFrequency = frequencyMinutes;
              registeredWifiOnly = wifiOnly;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('1 hour'));
      await tester.pumpAndSettle();

      expect(settings.refreshFrequencyMinutes, 60);
      expect(registeredFrequency, 60);
      expect(registeredWifiOnly, isFalse);
    });

    testWidgets('toggling wifi-only persists it and re-registers background sync', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsRepository(await SharedPreferences.getInstance());
      bool? registeredWifiOnly;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: SettingsScreen(
            onSignOut: () async {},
            settingsRepository: settings,
            onSyncSettingsChanged: ({required frequencyMinutes, required wifiOnly}) async {
              registeredWifiOnly = wifiOnly;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      expect(settings.wifiOnlySync, isTrue);
      expect(registeredWifiOnly, isTrue);
    });

    testWidgets('defaults to Dark selected in the theme selector', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsRepository(await SharedPreferences.getInstance());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: SettingsScreen(onSignOut: () async {}, settingsRepository: settings),
        ),
      );
      await tester.pumpAndSettle();

      final themeSelector = tester.widget<SegmentedButton<ThemeMode>>(find.byType(SegmentedButton<ThemeMode>));
      expect(themeSelector.selected, {ThemeMode.dark});
    });

    testWidgets('selecting Light persists it and updates ThemeController', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsRepository(await SharedPreferences.getInstance());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: SettingsScreen(onSignOut: () async {}, settingsRepository: settings),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();

      expect(settings.themeMode, ThemeMode.light);
      expect(ThemeController.mode.value, ThemeMode.light);
    });
  });
}
