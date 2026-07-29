import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Thin typed wrapper around [SharedPreferences] — the single source of
/// truth for every persisted app setting. Takes the [SharedPreferences]
/// instance as a constructor param (not a hidden singleton) so tests can
/// supply one seeded via [SharedPreferences.setMockInitialValues], and so
/// the background sync isolate (which has no access to the running app's
/// memory) can load its own copy fresh on every run.
class SettingsRepository {
  SettingsRepository(this._prefs);

  final SharedPreferences _prefs;

  static Future<SettingsRepository> load() async =>
      SettingsRepository(await SharedPreferences.getInstance());

  static const _lastSyncedAtKey = 'last_synced_at';
  static const _refreshFrequencyMinutesKey = 'refresh_frequency_minutes';
  static const _wifiOnlySyncKey = 'wifi_only_sync';
  static const _themeModeKey = 'theme_mode';
  static const _retentionExpireReadAfterDaysKey = 'retention_expire_read_after_days';
  static const _retentionCapPerFeedKey = 'retention_cap_per_feed';

  DateTime? get lastSyncedAt {
    final raw = _prefs.getString(_lastSyncedAtKey);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> setLastSyncedAt(DateTime time) => _prefs.setString(_lastSyncedAtKey, time.toIso8601String());

  /// Default of 15 matches today's hardcoded WorkManager interval — an
  /// upgrading user sees no behavior change until they opt into something
  /// else.
  int get refreshFrequencyMinutes => _prefs.getInt(_refreshFrequencyMinutesKey) ?? 15;

  Future<void> setRefreshFrequencyMinutes(int minutes) => _prefs.setInt(_refreshFrequencyMinutesKey, minutes);

  /// Default of false matches today's Constraints(networkType: connected)
  /// (any network) behavior.
  bool get wifiOnlySync => _prefs.getBool(_wifiOnlySyncKey) ?? false;

  Future<void> setWifiOnlySync(bool wifiOnly) => _prefs.setBool(_wifiOnlySyncKey, wifiOnly);

  /// Default of dark matches today's only theme — upgrading users see no
  /// change until they opt into light or system.
  ThemeMode get themeMode => switch (_prefs.getString(_themeModeKey)) {
        'light' => ThemeMode.light,
        'system' => ThemeMode.system,
        _ => ThemeMode.dark,
      };

  Future<void> setThemeMode(ThemeMode mode) => _prefs.setString(_themeModeKey, mode.name);

  /// Default of null (disabled) is critical for upgrade safety — nobody's
  /// downloaded library should get silently pruned the first time they
  /// open an updated app.
  int? get retentionExpireReadAfterDays => _prefs.getInt(_retentionExpireReadAfterDaysKey);

  Future<void> setRetentionExpireReadAfterDays(int? days) async {
    if (days == null) {
      await _prefs.remove(_retentionExpireReadAfterDaysKey);
    } else {
      await _prefs.setInt(_retentionExpireReadAfterDaysKey, days);
    }
  }

  /// Default of null (disabled) — see [retentionExpireReadAfterDays].
  int? get retentionCapPerFeed => _prefs.getInt(_retentionCapPerFeedKey);

  Future<void> setRetentionCapPerFeed(int? count) async {
    if (count == null) {
      await _prefs.remove(_retentionCapPerFeedKey);
    } else {
      await _prefs.setInt(_retentionCapPerFeedKey, count);
    }
  }
}
