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
    // before it returns, on every cold launch. frequency: nil defers to the plugin's own
    // default (15 minutes) for the interval used when the OS reschedules the task after it
    // runs — iOS treats this as a hint regardless (see background_sync.dart's comment); the
    // actual per-launch schedule still comes from Dart's Workmanager().registerPeriodicTask
    // call in BackgroundSync.register().
    WorkmanagerPlugin.registerPeriodicTask(withIdentifier: "deepread-periodic-sync", frequency: nil)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
