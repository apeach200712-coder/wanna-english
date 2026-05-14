import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    NSLog("[STARTUP_DIAG] iOS AppDelegate didFinishLaunching")
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Called from [SceneDelegate] after the scene creates its [FlutterEngine].
  /// Use the generated registrant so every iOS plugin matches `pubspec` and the
  /// engine’s expectations (manual registration can miss updates or ordering).
  func configureFlutterEngine(_ pluginRegistry: FlutterPluginRegistry, messenger: FlutterBinaryMessenger) {
    NSLog("[STARTUP_DIAG] iOS configureFlutterEngine (GeneratedPluginRegistrant)")
    GeneratedPluginRegistrant.register(with: pluginRegistry)
  }
}
