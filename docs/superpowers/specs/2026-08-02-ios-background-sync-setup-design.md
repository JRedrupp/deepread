# iOS background sync setup — design

## Problem

`BackgroundSync.register()` (`mobile/lib/features/sync/background_sync.dart`) calls
`Workmanager().registerPeriodicTask(...)`, which on iOS is backed by `BGTaskScheduler`. iOS
requires two things this app has never had: a `BGTaskSchedulerPermittedIdentifiers` entry in
`Info.plist` naming every task identifier the app may schedule, and (for this app's specific
Flutter setup, see below) an explicit native call re-registering the task's launch handler on
every cold start. Without them, `registerPeriodicTask` throws on iOS — caught by the try/catch in
`mobile/lib/main.dart`, so the app still starts, but background sync silently never runs. This is
the last genuinely unbuilt MVP item in TODO.md.

**Environment constraint:** this repo is developed on Linux with no Xcode/macOS available anywhere
in the dev environment, and no iPhone to test on. Every change below is grounded in reading the
installed `workmanager_apple` 0.9.6 plugin's actual Swift source
(`~/.pub-cache/hosted/pub.dev/workmanager_apple-0.9.6/ios/...`) rather than its README (which
points at an external docs site describing an older/different API shape — verified stale against
this installed version). The changes cannot be compiled or run locally; see the CI job below for
the only verification this environment can provide before a human with Mac/iPhone access checks it
for real.

## Design

### 1. `mobile/ios/Runner/Info.plist`

Add:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>
</array>
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>deepread-periodic-sync</string>
</array>
```

`deepread-periodic-sync` is the existing `_syncTaskName` constant in `background_sync.dart`,
reused as-is (Apple recommends but does not enforce reverse-DNS-style identifiers; reusing the
existing string avoids touching the Android-shared task name). Background Modes requires no
Xcode capability toggle or entitlements file — it's a plain Info.plist key, safely hand-editable
without Xcode.

### 2. `mobile/ios/Runner/AppDelegate.swift`

```swift
import Flutter
import UIKit
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    WorkmanagerPlugin.registerLaunchHandlers()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
```

`workmanager_apple` normally self-registers as an application delegate (`registrar.
addApplicationDelegate` in `WorkmanagerPlugin.register(with:)`), which would handle
re-registering previously-scheduled tasks' launch handlers automatically on cold start — no manual
code needed in the common case. This app doesn't hit the common case: it uses
`FlutterImplicitEngineDelegate` (plugins registered from `didInitializeImplicitFlutterEngine`,
confirmed in the current `AppDelegate.swift`) together with `UIApplicationSceneManifest`
(confirmed in `Info.plist`). The plugin's own source carries a doc comment stating that under the
UIScene lifecycle, plugin registration happens *after* `didFinishLaunchingWithOptions` returns —
too late for `BGTaskScheduler`, which only delivers a task to a relaunched app if its launch
handler was registered *during* that call. Apps on this pattern are directed to call
`WorkmanagerPlugin.registerLaunchHandlers()` themselves before it returns.

This call is a no-op read of persisted UserDefaults state on a fresh install (nothing scheduled
yet). Once the app's own Dart code calls `Workmanager().registerPeriodicTask(...)` post-launch (as
`BackgroundSync.register()` already does from `main.dart`), the plugin submits the `BGTaskScheduler`
request and registers the handler for the current process *and* persists the schedule so this
`AppDelegate` call can re-register it on every subsequent cold start.

Nothing else needs to change — no `registerPeriodicTask(withIdentifier:frequency:)`-style manual
scheduling call, no Podfile edits (this project has no `ios/Podfile`; plugins resolve via Flutter's
Swift Package Manager integration, confirmed via `FLUTTER_FRAMEWORK_SWIFT_PACKAGE_PATH` in
`ios/Flutter/Generated.xcconfig`).

### 3. CI: `mobile-ios-compile-check` job (`.github/workflows/ci.yml`)

New job, `runs-on: macos-latest` (separate from `mobile-test`'s `ubuntu-latest`, since iOS builds
need Xcode):

```yaml
mobile-ios-compile-check:
  runs-on: macos-latest
  defaults:
    run:
      working-directory: mobile
  steps:
    - uses: actions/checkout@v7
    - uses: subosito/flutter-action@v2
      with:
        channel: stable
        cache: true
    - run: flutter pub get
    - run: dart run build_runner build
    - run: flutter build ios --debug --no-codesign
```

Same rationale as the Android debug-build check added just before this branch: `flutter analyze`/
`flutter test` never touch native compilation, so a plugin bump that breaks the Swift build (the
exact failure mode that hit `workmanager_android` between v0.5.0 and v0.6.0) would otherwise only
surface at release-build time — which, for iOS, this project currently has no release pipeline to
even attempt. `--debug --no-codesign` mirrors the Android job's `--debug` choice (same compile step
as release, skips signing/codesigning which needs secrets this job shouldn't need) applied to the
iOS equivalent (`--no-codesign` skips the code-signing step, which needs an Apple
signing identity/certs not available in CI).

This job also happens to be the only verification available in this environment for step 2's
`import workmanager_apple` line — if the module name assumption is wrong, this job fails and says
so, rather than the mistake sitting silent until someone builds on a Mac.

**Cost tradeoff (explicitly accepted):** GitHub bills macOS runner minutes at 10x the Linux rate.
Confirmed acceptable with the user given the alternative (an iOS-breaking regression going
unnoticed until a real release attempt) is worse for a repo already burned once by exactly this
failure mode on Android.

### 4. Housekeeping

- `mobile/lib/main.dart`: update the catch-block comment that currently reads "e.g. iOS without the
  BGTaskSchedulerPermittedIdentifiers Info.plist entry — see TODO.md" to reflect that this is now
  wired up (comment should note the try/catch itself stays, since background registration failing
  for *other* reasons — e.g. a future iOS OS-level restriction — should still fail soft).
- `mobile/lib/features/sync/background_sync.dart`: update the inline comment at the
  `registerPeriodicTask` call site that currently says the Info.plist entries "aren't set up yet".
- `TODO.md`: remove the "iOS background fetch config" MVP item, since it's no longer unbuilt — but
  add a line to TECH_DEBT.md noting it is unverified on a real device/Mac/simulator, so it isn't
  silently treated as "confirmed working" until someone with Mac access checks it.

## Non-goals / accepted risk

- **No real-device or simulator verification.** This design closes the "genuinely unbuilt" gap
  TODO.md tracked, but does not close the "confirmed working" gap — that requires Mac/iPhone access
  this environment doesn't have. The new CI job catches compile-time breakage only; it cannot
  confirm `BGTaskScheduler` actually fires the task, since CI runners don't simulate real
  background-execution OS behavior (and even a real simulator's BGTaskScheduler timing is
  notoriously unreliable and normally needs a manual LLDB-triggered simulation to test at all).
- **No change to `BackgroundSync`'s Dart-level API or `background_sync.dart`'s scheduling logic.**
  This is purely the native-side wiring iOS requires; the existing frequency/wifi-only/re-registration
  behavior (documented in that file's comments) is unchanged.
- **Not addressed:** the OEM battery-restriction problem already tracked separately in TODO.md for
  Android (Settings-page-gated prompt) — out of scope, different platform, different root cause.
