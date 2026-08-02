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
