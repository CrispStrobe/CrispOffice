import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var terminationPending = false

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // The red traffic light closes the workspace window, not the application.
    return false
  }

  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag, let window = mainFlutterWindow {
      window.makeKeyAndOrderFront(self)
      sender.activate(ignoringOtherApps: true)
    }
    return true
  }

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if terminationPending { return .terminateLater }
    guard let controller = mainFlutterWindow?.contentViewController as? FlutterViewController else {
      return .terminateNow
    }
    terminationPending = true
    mainFlutterWindow?.makeKeyAndOrderFront(self)
    let channel = FlutterMethodChannel(
      name: "crispoffice/window",
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.invokeMethod("confirmQuit", arguments: nil) { [weak self] result in
      self?.terminationPending = false
      // Missing Flutter handlers and errors never silently discard documents.
      sender.reply(toApplicationShouldTerminate: (result as? Bool) == true)
    }
    return .terminateLater
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
