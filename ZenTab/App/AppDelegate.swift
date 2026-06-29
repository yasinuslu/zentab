import AppKit

/// Drives startup. The app is an accessory (`.accessory` activation + `LSUIElement`):
/// no Dock icon, no app menu, just the menu bar item and the non-activating overlay.
final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    AppModel.shared.bootstrap()
  }
}
