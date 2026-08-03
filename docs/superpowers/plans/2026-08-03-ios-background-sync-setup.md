# iOS Background Sync Setup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire up the native iOS configuration `BackgroundSync.register()` (`mobile/lib/features/sync/background_sync.dart`) has needed since it was written — `Info.plist` background-task keys and an `AppDelegate.swift` registration call — and add a CI job that compiles the iOS target so this can't silently regress.

**Architecture:** Three plain config/code edits (Info.plist, AppDelegate.swift, ci.yml) plus doc cleanup. No Dart-level API changes. Full detail and rationale: `docs/superpowers/specs/2026-08-02-ios-background-sync-setup-design.md`.

**Tech Stack:** Flutter/Dart (`workmanager` 0.10.1 / `workmanager_apple` 0.9.6), Swift (iOS `AppDelegate.swift`), GitHub Actions (`macos-latest` runner).

> **Superseded:** Task 2's `AppDelegate.swift` approach below was written against the wrong
> `workmanager_apple` version and corrected after implementation — see the Addendum at the end of
> the design doc (`docs/superpowers/specs/2026-08-02-ios-background-sync-setup-design.md`) for what
> actually shipped and why.

## Global Constraints

- No macOS/Xcode/iPhone/simulator available in this dev environment — every native-code step here is unverifiable locally. The only verification available before a human with Mac access checks it for real is: (a) local syntax/structure checks using Python's stdlib `plistlib`/`yaml`, and (b) the new CI job actually compiling on a `macos-latest` GitHub Actions runner once pushed.
- Task identifier must be exactly `deepread-periodic-sync` everywhere it appears (this is `_syncTaskName` in `mobile/lib/features/sync/background_sync.dart:7`) — `BGTaskScheduler` errors (`BGTaskSchedulerErrorDomain Code 3`) if the Info.plist entry and the Dart-registered identifier don't match exactly.
- iOS deployment target is 13.0 (`mobile/ios/Runner.xcodeproj/project.pbxproj`) — matches `BGTaskScheduler`'s own iOS 13+ minimum, so no `#available` guards are needed in `AppDelegate.swift`.
- This project has no `ios/Podfile` — plugins resolve via Flutter's Swift Package Manager integration (confirmed via `FLUTTER_FRAMEWORK_SWIFT_PACKAGE_PATH` in `ios/Flutter/Generated.xcconfig`). Do not add a Podfile or CocoaPods steps.
- Follow this repo's Gitflow: branch `feature/ios-background-sync-setup` off `develop` (already created), PR back into `develop`.

---

### Task 1: Info.plist background-task configuration

**Files:**
- Modify: `mobile/ios/Runner/Info.plist`

**Interfaces:**
- Produces: the string `deepread-periodic-sync` registered in `BGTaskSchedulerPermittedIdentifiers` — Task 2's `AppDelegate.swift` change and the existing Dart code in `background_sync.dart:7` both depend on this exact string already; this task doesn't change the Dart side, only makes the native side match it.

- [ ] **Step 1: Add the two required keys to Info.plist**

Open `mobile/ios/Runner/Info.plist`. It's a standard XML plist with keys in alphabetical-ish groupings (not strictly sorted — e.g. `LSRequiresIPhoneOS` sits before `UIApplicationSceneManifest`). Insert the two new keys immediately before the closing `</dict>` (i.e. after the `UISupportedInterfaceOrientations~ipad` block, currently the last entry):

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

Match the file's existing indentation style (tabs, one level under `<dict>`).

- [ ] **Step 2: Verify the plist is well-formed and has the expected values**

Run (from repo root):

```bash
python3 -c "
import plistlib
with open('mobile/ios/Runner/Info.plist', 'rb') as f:
    d = plistlib.load(f)
assert d['UIBackgroundModes'] == ['fetch'], d.get('UIBackgroundModes')
assert d['BGTaskSchedulerPermittedIdentifiers'] == ['deepread-periodic-sync'], d.get('BGTaskSchedulerPermittedIdentifiers')
print('OK')
"
```

Expected: prints `OK`. If it raises `xml.parsers.expat.ExpatError`, the XML is malformed (e.g. an unclosed tag) — fix and re-run before continuing. This is the only automated check available in this environment; it confirms the file parses as a valid plist and has the right values, but cannot confirm iOS itself accepts it (that's Task 4's CI job).

- [ ] **Step 3: Commit**

```bash
git add mobile/ios/Runner/Info.plist
git commit -m "Add BGTaskScheduler Info.plist entries for iOS background sync"
```

---

### Task 2: AppDelegate.swift native registration + CI compile-check job

**Files:**
- Modify: `mobile/ios/Runner/AppDelegate.swift`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: the `deepread-periodic-sync` identifier from Task 1 (indirectly — `WorkmanagerPlugin.registerLaunchHandlers()` re-registers whatever was previously scheduled via Dart; it doesn't take the identifier as a literal in this file).
- Produces: nothing consumed by later tasks directly, but this task's correctness (does `import workmanager_apple` actually resolve? does `WorkmanagerPlugin.registerLaunchHandlers()` exist with this exact signature?) can only be confirmed via the CI job added in this same task, run in Task 4.

- [ ] **Step 1: Edit AppDelegate.swift**

Current content of `mobile/ios/Runner/AppDelegate.swift`:

```swift
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
```

Replace it with:

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
    // workmanager_apple normally re-registers a previously-scheduled task's
    // BGTaskScheduler launch handler on its own (as an auto-added application
    // delegate). That happens too late here: this app uses the UIScene
    // lifecycle + FlutterImplicitEngineDelegate, under which Flutter registers
    // plugins from didInitializeImplicitFlutterEngine (after this method
    // returns) rather than during it — see WorkmanagerPlugin.registerLaunchHandlers()'s
    // doc comment in the workmanager_apple plugin source. BGTaskScheduler only
    // delivers a task to a relaunched app if the launch handler was registered
    // during didFinishLaunchingWithOptions, so it must be called explicitly,
    // here, before this method returns.
    WorkmanagerPlugin.registerLaunchHandlers()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
```

- [ ] **Step 2: Add the `mobile-ios-compile-check` job to ci.yml**

Current end of `.github/workflows/ci.yml` (`mobile-test` job, ending with the Android compile-check step added the previous commit):

```yaml
      - name: Compile-check the Android build
        # Catches native/Gradle build breakage that flutter analyze/flutter test
        # can't see (e.g. a pubspec.lock bump that silently breaks Kotlin plugin
        # compilation — see v0.6.0's release). Debug, not release: same Kotlin/Java
        # compile step runs for every build variant, so debug catches this equally
        # well while skipping R8/minification/signing — no release secrets needed
        # here since --dart-define values don't affect whether it compiles.
        run: flutter build apk --debug
```

Append a new top-level job after `mobile-test` (same indentation level as `backend-test`/`mobile-test`, i.e. two spaces under `jobs:`):

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
      - name: Compile-check the iOS build
        # Same rationale as mobile-test's Android compile-check: flutter
        # analyze/flutter test never touch native Swift compilation, so a
        # plugin bump or native-code change (e.g. AppDelegate.swift) that
        # breaks the iOS build would otherwise only surface at release-build
        # time — which this project currently has no pipeline to even attempt
        # for iOS. --debug mirrors the Android job (same compile step as
        # release, skips extra work); --no-codesign skips code-signing, which
        # needs an Apple signing identity/certs not available in CI.
        run: flutter build ios --debug --no-codesign
```

- [ ] **Step 3: Verify ci.yml is valid YAML**

Run (from repo root):

```bash
python3 -c "
import yaml
with open('.github/workflows/ci.yml') as f:
    d = yaml.safe_load(f)
assert 'mobile-ios-compile-check' in d['jobs'], list(d['jobs'])
assert d['jobs']['mobile-ios-compile-check']['runs-on'] == 'macos-latest'
print('OK')
"
```

Expected: prints `OK`.

- [ ] **Step 4: Commit**

```bash
git add mobile/ios/Runner/AppDelegate.swift .github/workflows/ci.yml
git commit -m "Register BGTaskScheduler launch handler in AppDelegate; add iOS compile-check CI job"
```

---

### Task 3: Doc/comment cleanup

**Files:**
- Modify: `mobile/lib/main.dart:24-25`
- Modify: `mobile/lib/features/sync/background_sync.dart:43-45`
- Modify: `TODO.md:1-9`
- Modify: `TECH_DEBT.md` (append)

**Interfaces:**
- None — this task only touches comments and docs, no code behavior changes.

- [ ] **Step 1: Update the comment in main.dart**

Current (`mobile/lib/main.dart:20-29`):

```dart
  try {
    await BackgroundSync.register(
      frequencyMinutes: settings.refreshFrequencyMinutes,
      wifiOnly: settings.wifiOnlySync,
    );
  } catch (e) {
    // Background registration failing (e.g. iOS without the
    // BGTaskSchedulerPermittedIdentifiers Info.plist entry — see
    // TODO.md) shouldn't prevent the app from starting. Manual "sync
    // now" still works either way.
    log('BackgroundSync.register failed: $e', name: 'main');
  }
```

Replace the comment (keep the try/catch structure unchanged — registration can still fail for other reasons, e.g. a future OS-level restriction):

```dart
  try {
    await BackgroundSync.register(
      frequencyMinutes: settings.refreshFrequencyMinutes,
      wifiOnly: settings.wifiOnlySync,
    );
  } catch (e) {
    // iOS's Info.plist/AppDelegate registration is wired up (see
    // TECH_DEBT.md — unverified on real hardware), but background
    // registration failing for other reasons (e.g. a future OS-level
    // restriction) still shouldn't prevent the app from starting. Manual
    // "sync now" still works either way.
    log('BackgroundSync.register failed: $e', name: 'main');
  }
```

- [ ] **Step 2: Update the comment in background_sync.dart**

Current (`mobile/lib/features/sync/background_sync.dart:38-53`):

```dart
  static Future<void> register({required int frequencyMinutes, required bool wifiOnly}) async {
    await Workmanager().initialize(backgroundSyncDispatcher);
    await Workmanager().registerPeriodicTask(
      _syncTaskName,
      _syncTaskName,
      // iOS treats this as a hint, not a guarantee (BGTaskScheduler decides
      // actual timing). See TODO.md — iOS also needs Info.plist entries
      // (BGTaskSchedulerPermittedIdentifiers) that aren't set up yet.
      //
      // Re-registering with a different frequency/wifiOnly later (e.g. from
      // the Settings screen) relies on ExistingPeriodicWorkPolicy defaulting
      // to UPDATE on Android, which updates this work's schedule/constraints
      // in place rather than leaving the old registration running.
      frequency: backgroundSyncFrequency(frequencyMinutes),
      constraints: Constraints(networkType: backgroundSyncNetworkType(wifiOnly: wifiOnly)),
    );
  }
```

Replace with:

```dart
  static Future<void> register({required int frequencyMinutes, required bool wifiOnly}) async {
    await Workmanager().initialize(backgroundSyncDispatcher);
    await Workmanager().registerPeriodicTask(
      _syncTaskName,
      _syncTaskName,
      // iOS treats this as a hint, not a guarantee (BGTaskScheduler decides
      // actual timing). Info.plist's BGTaskSchedulerPermittedIdentifiers entry
      // and AppDelegate.swift's launch-handler registration are wired up — see
      // TECH_DEBT.md for the "unverified on real hardware" caveat.
      //
      // Re-registering with a different frequency/wifiOnly later (e.g. from
      // the Settings screen) relies on ExistingPeriodicWorkPolicy defaulting
      // to UPDATE on Android, which updates this work's schedule/constraints
      // in place rather than leaving the old registration running.
      frequency: backgroundSyncFrequency(frequencyMinutes),
      constraints: Constraints(networkType: backgroundSyncNetworkType(wifiOnly: wifiOnly)),
    );
  }
```

- [ ] **Step 3: Remove the resolved item from TODO.md**

Current (`TODO.md:1-9`):

```markdown
# TODO

## MVP — remaining (not yet built, not deferred)

Auth screens, the sync service, and add-feed wiring are now built and working end-to-end. What's left from the original MVP scope:

- [ ] **iOS background fetch config.** `BackgroundSync.register()` (`mobile/lib/features/sync/background_sync.dart`) calls `Workmanager().registerPeriodicTask`, but iOS also needs a `BGTaskSchedulerPermittedIdentifiers` entry in `Info.plist` (and corresponding native setup) that hasn't been added — registration is wrapped in try/catch so this fails soft rather than crashing the app, but background sync silently won't run on iOS until this is done.

Everything below this section is genuinely deferred/out-of-scope for the MVP, not missing MVP work.

## Features
```

Replace lines 1-9 with:

```markdown
# TODO

MVP scope (auth screens, sync service, add-feed wiring, and iOS background sync config) is now
fully built. Everything below is deferred/out-of-scope for the MVP, not missing MVP work.

## Features
```

- [ ] **Step 4: Add the unverified-on-hardware caveat to TECH_DEBT.md**

Append this bullet to the end of `TECH_DEBT.md` (after the existing "Local-data wipe on sign-out" bullet, matching the file's existing bullet style):

```markdown
- **iOS background sync is wired up but unverified on real hardware.** `BGTaskSchedulerPermittedIdentifiers`/`UIBackgroundModes` (`mobile/ios/Runner/Info.plist`) and the `WorkmanagerPlugin.registerLaunchHandlers()` call (`mobile/ios/Runner/AppDelegate.swift`) were added by reading the `workmanager_apple` plugin's source directly, in a dev environment with no macOS/Xcode/iPhone available to build or run it. `.github/workflows/ci.yml`'s `mobile-ios-compile-check` job (macOS runner) confirms it compiles, but `BGTaskScheduler`'s actual background-execution behavior — whether the task fires, how often, under what OS conditions — has never been observed on a real device or simulator. Treat as unconfirmed until someone with Mac/iPhone access checks it.
```

- [ ] **Step 5: Verify no stale references remain**

Run (from repo root):

```bash
grep -n "aren't set up yet\|BGTaskSchedulerPermittedIdentifiers entry — see\|iOS background fetch config" mobile/lib/main.dart mobile/lib/features/sync/background_sync.dart TODO.md
```

Expected: no output (all three patterns removed).

- [ ] **Step 6: Commit**

```bash
git add mobile/lib/main.dart mobile/lib/features/sync/background_sync.dart TODO.md TECH_DEBT.md
git commit -m "Update docs/comments now that iOS background sync config is wired up"
```

---

### Task 4: Push, open PR, confirm CI

**Files:** none (verification-only task)

**Interfaces:** none

- [ ] **Step 1: Push the branch**

```bash
git push -u origin feature/ios-background-sync-setup
```

- [ ] **Step 2: Open the PR against develop**

```bash
gh pr create --base develop --title "Wire up iOS background sync config" --body "$(cat <<'EOF'
## Summary
- Adds the BGTaskScheduler Info.plist entries and AppDelegate.swift launch-handler
  registration that mobile/lib/features/sync/background_sync.dart's BackgroundSync.register()
  has needed since it was written (see TODO.md).
- Adds a mobile-ios-compile-check CI job (macos-latest) mirroring the existing Android
  debug-build check, since flutter analyze/flutter test never touch native compilation.

## Test plan
- [x] Info.plist parses via plistlib with the expected keys/values (local, see commit history)
- [x] ci.yml parses as valid YAML with the new job present (local, see commit history)
- [ ] mobile-ios-compile-check job passes on the actual macos-latest runner (this PR's own CI run)
- [ ] Unverified: BGTaskScheduler actually fires the task on a real device/simulator — no
      Mac/iPhone access in the dev environment; see TECH_DEBT.md

Design doc: docs/superpowers/specs/2026-08-02-ios-background-sync-setup-design.md
EOF
)"
```

- [ ] **Step 3: Wait for CI and check the result**

```bash
gh pr checks --watch
```

Expected: `backend-test`, `mobile-test`, and `mobile-ios-compile-check` all report `pass`.

- If `mobile-ios-compile-check` fails, read the failure log (`gh run view --log-failed` or the URL `gh pr checks` prints) before making any further changes — do not guess. The most likely failure points, in order of likelihood: (a) `import workmanager_apple` not resolving (wrong module name), (b) the plist keys rejected for a formatting reason `plistlib` wouldn't catch (e.g. Xcode-specific plist quirks), (c) an unrelated pre-existing Flutter/Xcode-version mismatch on the runner image. Stop and report back rather than iterating blindly, since this is the first real signal from an actual Apple toolchain in this whole task.
- If it passes, the task (and this plan) is complete.
