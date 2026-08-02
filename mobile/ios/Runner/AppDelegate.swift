import Flutter
import UIKit
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // workmanager_apple 0.9.1+2 (pinned in pubspec.yaml's dependency_overrides for an
    // unrelated Android AGP-9 Gradle issue — see that file's comment) has no
    // auto-registration path for BGTaskScheduler: registerPeriodicTask(request:), the
    // Dart-invoked host API, only ever calls BGTaskScheduler.shared.submit(...) — it never
    // calls BGTaskScheduler.shared.register(forTaskWithIdentifier:using:). The only place
    // that ever registers the launch handler is this static method, and Apple requires
    // that registration to happen synchronously during didFinishLaunchingWithOptions,
    // before it returns, on every cold launch. registerPeriodicTask(request:) only ever
    // forwards request.initialDelaySeconds (always 0 from this app's Dart call site) to
    // schedulePeriodicTask — the frequency: Duration passed to Dart's
    // Workmanager().registerPeriodicTask call (background_sync.dart) is never read by the
    // iOS host API at all; it only affects the Android path. On iOS, frequency: nil here is
    // what actually governs the reschedule interval, deferring permanently to the plugin's
    // own hardcoded 15-minute default regardless of the frequency the user picks in the
    // Settings screen (see TECH_DEBT.md for the Android/iOS divergence this causes).
    WorkmanagerPlugin.registerPeriodicTask(withIdentifier: "deepread-periodic-sync", frequency: nil)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
