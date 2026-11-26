import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Keep real AppKit traffic lights and their native zoom/fullscreen behavior.
    // Flutter paints beneath the transparent title bar and reserves its leading
    // 80 points for these controls. Closing retains this window for Dock reopen.
    styleMask.insert(.fullSizeContentView)
    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    isReleasedWhenClosed = false
    collectionBehavior.insert(.fullScreenPrimary)
    for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
      standardWindowButton(button)?.isHidden = false
    }

    RegisterGeneratedPlugins(registry: flutterViewController)
    (NSApplication.shared.delegate as? AppDelegate)?.registerCustomKeychainChannel(
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    (NSApplication.shared.delegate as? AppDelegate)?.biometricVaultKeychain.register(
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    (NSApplication.shared.delegate as? AppDelegate)?.registerRecentFilesChannel(
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    (NSApplication.shared.delegate as? AppDelegate)?.registerMailPasteboardChannel(
      binaryMessenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}
