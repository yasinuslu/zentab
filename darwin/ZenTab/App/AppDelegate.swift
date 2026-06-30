import AppKit

/// Drives startup. The app is an accessory (`.accessory` activation + `LSUIElement`):
/// no Dock icon, no app menu, just the menu bar item and the non-activating overlay.
final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    AppModel.shared.bootstrap()
  }

  func applicationWillTerminate(_ notification: Notification) {
    // The native symbolic-hotkey disable persists after we exit, so hand Cmd+Tab back
    // to macOS on a clean quit — you're never left with a dead key when ZenTab is off.
    AppModel.shared.shutdown()
  }
}
