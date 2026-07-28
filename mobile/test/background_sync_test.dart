import 'package:deepread/features/sync/background_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workmanager/workmanager.dart';

void main() {
  group('backgroundSyncFrequency', () {
    for (final minutes in [15, 30, 60, 180]) {
      test('maps $minutes minutes to a Duration of the same length', () {
        expect(backgroundSyncFrequency(minutes), Duration(minutes: minutes));
      });
    }
  });

  group('backgroundSyncNetworkType', () {
    test('any network when wifiOnly is false (matches today\'s behavior)', () {
      expect(backgroundSyncNetworkType(wifiOnly: false), NetworkType.connected);
    });

    test('unmetered only when wifiOnly is true', () {
      expect(backgroundSyncNetworkType(wifiOnly: true), NetworkType.unmetered);
    });
  });
}
