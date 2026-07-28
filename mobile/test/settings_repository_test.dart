import 'package:deepread/features/settings/settings_repository.dart';
import 'package:flutter/material.dart';
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

  test('themeMode defaults to dark (matches today\'s only theme, so upgrading users see no change)', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = SettingsRepository(await SharedPreferences.getInstance());

    expect(repo.themeMode, ThemeMode.dark);
  });

  test('setThemeMode persists light', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = SettingsRepository(await SharedPreferences.getInstance());

    await repo.setThemeMode(ThemeMode.light);

    final reloaded = SettingsRepository(await SharedPreferences.getInstance());
    expect(reloaded.themeMode, ThemeMode.light);
  });

  test('setThemeMode persists system', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = SettingsRepository(await SharedPreferences.getInstance());

    await repo.setThemeMode(ThemeMode.system);

    final reloaded = SettingsRepository(await SharedPreferences.getInstance());
    expect(reloaded.themeMode, ThemeMode.system);
  });

  test('retentionExpireReadAfterDays defaults to null (disabled, so upgrading users keep everything)', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = SettingsRepository(await SharedPreferences.getInstance());

    expect(repo.retentionExpireReadAfterDays, isNull);
  });

  test('setRetentionExpireReadAfterDays persists a value and can clear it back to null', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = SettingsRepository(await SharedPreferences.getInstance());

    await repo.setRetentionExpireReadAfterDays(30);
    expect(SettingsRepository(await SharedPreferences.getInstance()).retentionExpireReadAfterDays, 30);

    await repo.setRetentionExpireReadAfterDays(null);
    expect(SettingsRepository(await SharedPreferences.getInstance()).retentionExpireReadAfterDays, isNull);
  });

  test('retentionCapPerFeed defaults to null (disabled)', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = SettingsRepository(await SharedPreferences.getInstance());

    expect(repo.retentionCapPerFeed, isNull);
  });

  test('setRetentionCapPerFeed persists a value and can clear it back to null', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = SettingsRepository(await SharedPreferences.getInstance());

    await repo.setRetentionCapPerFeed(50);
    expect(SettingsRepository(await SharedPreferences.getInstance()).retentionCapPerFeed, 50);

    await repo.setRetentionCapPerFeed(null);
    expect(SettingsRepository(await SharedPreferences.getInstance()).retentionCapPerFeed, isNull);
  });
}
