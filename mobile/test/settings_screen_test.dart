import 'package:deepread/data/local/database.dart';
import 'package:deepread/features/settings/settings_repository.dart';
import 'package:deepread/features/settings/settings_screen.dart';
import 'package:deepread/theme/app_theme.dart';
import 'package:deepread/theme/theme_controller.dart';
import 'package:drift/native.dart';
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

  group('formatBytes', () {
    test('formats bytes under 1 KB as B', () {
      expect(formatBytes(512), '512 B');
    });

    test('formats kilobytes', () {
      expect(formatBytes(2048), '2.0 KB');
    });

    test('formats megabytes', () {
      expect(formatBytes(5 * 1024 * 1024), '5.0 MB');
    });

    test('formats gigabytes', () {
      expect(formatBytes(2 * 1024 * 1024 * 1024), '2.00 GB');
    });
  });

  group('SettingsScreen', () {
    late AppDatabase db;

    // computeStorageBytes/onClearDownloaded are always overridden below with
    // fakes that do no real file I/O — real dart:io operations (as the true
    // RetentionService performs) don't reliably complete under
    // testWidgets'/pumpAndSettle's fake-async zone without `tester.runAsync`,
    // the same class of issue TECH_DEBT.md documents for drift .watch()
    // streams. RetentionService's actual eviction/storage-computation logic
    // is covered directly in retention_service_test.dart (plain `test()`
    // bodies, no widget pumping) and its SyncService wiring in
    // sync_service_test.dart — this file only needs to prove SettingsScreen
    // wires taps to whatever callbacks it's given.
    Future<int> noStorage(AppDatabase _) async => 0;
    Future<void> noOpClear(AppDatabase _) async {}

    setUp(() {
      ThemeController.mode.value = ThemeMode.dark;
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() => db.close());

    // The settings list keeps growing new sections; rather than fixing a
    // scroll offset that breaks again next time, give the test surface a
    // tall viewport so the whole ListView fits without scrolling at all.
    Future<void> pumpTall(WidgetTester tester, Widget home) async {
      tester.view.physicalSize = const Size(800, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(theme: AppTheme.dark(), home: home));
    }

    testWidgets('shows Never when nothing has synced yet', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsRepository(await SharedPreferences.getInstance());

      await pumpTall(
        tester,
        SettingsScreen(
          onSignOut: () async {},
          settingsRepository: settings,
          db: db,
          computeStorageBytes: noStorage,
          onClearDownloaded: noOpClear,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Never'), findsOneWidget);
    });

    testWidgets('shows the persisted last-synced time', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsRepository(await SharedPreferences.getInstance());
      await settings.setLastSyncedAt(DateTime(2026, 7, 28, 9, 5));

      await pumpTall(
        tester,
        SettingsScreen(
          onSignOut: () async {},
          settingsRepository: settings,
          db: db,
          computeStorageBytes: noStorage,
          onClearDownloaded: noOpClear,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('2026-07-28 09:05'), findsOneWidget);
    });

    testWidgets('tapping Sign out invokes the callback and pops back to the previous route', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsRepository(await SharedPreferences.getInstance());
      var signOutCalls = 0;

      await pumpTall(
        tester,
        Builder(
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
                      db: db,
                      computeStorageBytes: noStorage,
                      onClearDownloaded: noOpClear,
                    ),
                  ),
                ),
                child: const Text('open settings'),
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

    testWidgets('defaults to the 15 min preset and wifi-only off', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsRepository(await SharedPreferences.getInstance());

      await pumpTall(
        tester,
        SettingsScreen(
          onSignOut: () async {},
          settingsRepository: settings,
          db: db,
          computeStorageBytes: noStorage,
          onClearDownloaded: noOpClear,
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

      await pumpTall(
        tester,
        SettingsScreen(
          onSignOut: () async {},
          settingsRepository: settings,
          db: db,
          computeStorageBytes: noStorage,
          onClearDownloaded: noOpClear,
          onSyncSettingsChanged: ({required frequencyMinutes, required wifiOnly}) async {
            registeredFrequency = frequencyMinutes;
            registeredWifiOnly = wifiOnly;
          },
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

      await pumpTall(
        tester,
        SettingsScreen(
          onSignOut: () async {},
          settingsRepository: settings,
          db: db,
          computeStorageBytes: noStorage,
          onClearDownloaded: noOpClear,
          onSyncSettingsChanged: ({required frequencyMinutes, required wifiOnly}) async {
            registeredWifiOnly = wifiOnly;
          },
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

      await pumpTall(
        tester,
        SettingsScreen(
          onSignOut: () async {},
          settingsRepository: settings,
          db: db,
          computeStorageBytes: noStorage,
          onClearDownloaded: noOpClear,
        ),
      );
      await tester.pumpAndSettle();

      final themeSelector = tester.widget<SegmentedButton<ThemeMode>>(find.byType(SegmentedButton<ThemeMode>));
      expect(themeSelector.selected, {ThemeMode.dark});
    });

    testWidgets('selecting Light persists it and updates ThemeController', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsRepository(await SharedPreferences.getInstance());

      await pumpTall(
        tester,
        SettingsScreen(
          onSignOut: () async {},
          settingsRepository: settings,
          db: db,
          computeStorageBytes: noStorage,
          onClearDownloaded: noOpClear,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();

      expect(settings.themeMode, ThemeMode.light);
      expect(ThemeController.mode.value, ThemeMode.light);
    });

    testWidgets('shows computed storage usage and defaults retention controls to Off', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsRepository(await SharedPreferences.getInstance());

      await pumpTall(
        tester,
        SettingsScreen(
          onSignOut: () async {},
          settingsRepository: settings,
          db: db,
          computeStorageBytes: (_) async => 10,
          onClearDownloaded: noOpClear,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('10 B'), findsOneWidget);
      final expireSegmented =
          tester.widget<SegmentedButton<int?>>(find.byKey(const Key('retention-expire-segmented')));
      expect(expireSegmented.selected, {null});
      final capSegmented = tester.widget<SegmentedButton<int?>>(find.byKey(const Key('retention-cap-segmented')));
      expect(capSegmented.selected, {null});
    });

    testWidgets('selecting an expire-after preset persists it', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsRepository(await SharedPreferences.getInstance());

      await pumpTall(
        tester,
        SettingsScreen(
          onSignOut: () async {},
          settingsRepository: settings,
          db: db,
          computeStorageBytes: noStorage,
          onClearDownloaded: noOpClear,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('30 days'));
      await tester.pumpAndSettle();

      expect(settings.retentionExpireReadAfterDays, 30);
    });

    testWidgets('selecting a cap-per-feed preset persists it', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsRepository(await SharedPreferences.getInstance());

      await pumpTall(
        tester,
        SettingsScreen(
          onSignOut: () async {},
          settingsRepository: settings,
          db: db,
          computeStorageBytes: noStorage,
          onClearDownloaded: noOpClear,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('50'));
      await tester.pumpAndSettle();

      expect(settings.retentionCapPerFeed, 50);
    });

    testWidgets('Clear downloaded articles asks for confirmation, then clears and refreshes usage', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsRepository(await SharedPreferences.getInstance());
      var cleared = false;

      await pumpTall(
        tester,
        SettingsScreen(
          onSignOut: () async {},
          settingsRepository: settings,
          db: db,
          computeStorageBytes: (_) async => cleared ? 0 : 100,
          onClearDownloaded: (_) async => cleared = true,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('100 B'), findsOneWidget);

      await tester.tap(find.text('Clear downloaded articles'));
      await tester.pumpAndSettle();

      expect(find.text('Clear downloaded articles?'), findsOneWidget);
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();

      expect(cleared, isTrue);
      expect(find.text('0 B'), findsOneWidget);
    });
  });
}
