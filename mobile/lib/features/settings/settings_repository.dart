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

  DateTime? get lastSyncedAt {
    final raw = _prefs.getString(_lastSyncedAtKey);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> setLastSyncedAt(DateTime time) => _prefs.setString(_lastSyncedAtKey, time.toIso8601String());
}
