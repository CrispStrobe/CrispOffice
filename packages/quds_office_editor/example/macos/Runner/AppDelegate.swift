import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  @IBAction func showCrispOfficeAbout(_ sender: Any?) {
    guard let window = NSApplication.shared.windows.first(where: {
      $0.contentViewController is FlutterViewController
    }), let controller = window.contentViewController as? FlutterViewController else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "crispoffice/about",
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.invokeMethod("show", arguments: nil)
  }
}
