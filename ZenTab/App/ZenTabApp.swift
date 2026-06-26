import SwiftUI

/// ZenTab: a calm, single-window macOS app starter.
///
/// The entire app is intentionally small: one window, one view, one tiny model.
/// It is meant as a clean foundation you can grow into a real product.
@main
struct ZenTabApp: App {
    var body: some Scene {
        Window("ZenTab", id: "main") {
            ContentView()
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 440, height: 560)
    }
}
