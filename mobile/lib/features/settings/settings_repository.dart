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
}
