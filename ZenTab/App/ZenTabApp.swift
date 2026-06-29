import SwiftUI

/// ZenTab: a free, opinionated macOS window switcher.
///
/// There is no main window. The app is a menu bar accessory; switching happens in a
/// hand-rolled, non-activating AppKit overlay driven by a global hotkey (see
/// `AppModel` / `OverlayController`). SwiftUI is used only for the menu bar UI.
@main
struct ZenTabApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @StateObject private var model = AppModel.shared

  var body: some Scene {
    MenuBarExtra("ZenTab", systemImage: "rectangle.on.rectangle") {
      MenuBarContent(model: model)
    }
  }
}
