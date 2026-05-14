import Flutter
import UIKit

final class SafeFlutterViewController: FlutterViewController {
  @objc func createTouchRateCorrectionVSyncClientIfNeeded() {
    NSLog("[STARTUP_DIAG] iOS touch-rate correction vsync disabled")
  }
}