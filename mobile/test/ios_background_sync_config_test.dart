import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Must match the `_syncTaskName` constant in
// mobile/lib/features/sync/background_sync.dart:7. Hardcoded here (rather than imported)
// because that constant is private to background_sync.dart.
//
// If this identifier ever drifts out of sync between background_sync.dart, Info.plist, and
// AppDelegate.swift, BGTaskScheduler throws BGTaskSchedulerErrorDomain Code 3 at runtime on
// iOS — silently, since it's swallowed by main.dart's try/catch — and that's only observable
// on a real device, which nobody working on this repo currently has. This test catches the
// drift at CI time instead.
const _syncTaskId = 'deepread-periodic-sync';

void main() {
  group('iOS background sync identifier consistency', () {
    test('Info.plist declares the sync task identifier', () {
      final contents = File('ios/Runner/Info.plist').readAsStringSync();
      expect(contents, contains(_syncTaskId));
    });

    test('AppDelegate.swift registers the sync task identifier', () {
      final contents = File('ios/Runner/AppDelegate.swift').readAsStringSync();
      expect(contents, contains(_syncTaskId));
    });
  });
}
