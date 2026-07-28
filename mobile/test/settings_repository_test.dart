import 'package:deepread/features/settings/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('lastSyncedAt is null before anything is recorded', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = SettingsRepository(await SharedPreferences.getInstance());

    expect(repo.lastSyncedAt, isNull);
  });

  test('setLastSyncedAt persists a value readable back via a new instance', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = SettingsRepository(await SharedPreferences.getInstance());
    final time = DateTime.utc(2026, 7, 28, 12, 30);

    await repo.setLastSyncedAt(time);

    final reloaded = SettingsRepository(await SharedPreferences.getInstance());
    expect(reloaded.lastSyncedAt, time);
  });

  test('refreshFrequencyMinutes defaults to 15 (matches today\'s hardcoded interval)', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = SettingsRepository(await SharedPreferences.getInstance());

    expect(repo.refreshFrequencyMinutes, 15);
  });

  test('setRefreshFrequencyMinutes persists a chosen preset', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = SettingsRepository(await SharedPreferences.getInstance());

    await repo.setRefreshFrequencyMinutes(60);

    final reloaded = SettingsRepository(await SharedPreferences.getInstance());
    expect(reloaded.refreshFrequencyMinutes, 60);
  });

  test('wifiOnlySync defaults to false (matches today\'s any-network behavior)', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = SettingsRepository(await SharedPreferences.getInstance());

    expect(repo.wifiOnlySync, isFalse);
  });

  test('setWifiOnlySync persists true', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = SettingsRepository(await SharedPreferences.getInstance());

    await repo.setWifiOnlySync(true);

    final reloaded = SettingsRepository(await SharedPreferences.getInstance());
    expect(reloaded.wifiOnlySync, isTrue);
  });
}
