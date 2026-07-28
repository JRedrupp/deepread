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
}
