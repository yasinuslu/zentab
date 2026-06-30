import SwiftUI

/// The menu bar dropdown. Non-hot UI, so SwiftUI is the right tool here. It leads
/// with whether ZenTab is capturing its shortcut (the same truth the menu bar icon
/// shows), then permission actions, a private-API diagnostics smoke test, and Quit.
struct MenuBarContent: View {
  @ObservedObject var model: AppModel

  var body: some View {
    // Capture status: ZenTab never falls back to another key, so this just reports
    // whether we currently own the shortcut, and why not when we don't.
    Text(model.captureHealth.summary)
    if !model.accessibilityTrusted {
      Button("Grant Accessibility…") { model.requestAccessibility() }
    }

    Text("\(model.profile.label) shortcuts — \(shortcutHint)")
      .font(.caption)
    if model.profile == .development {
      Text("Run bin/run-prod to test the real Cmd+Tab suite.")
        .font(.caption)
    }

    Divider()

    if model.screenRecordingGranted {
      Text("Live thumbnails: on")
    } else {
      Button("Enable live thumbnails (Screen Recording)…") {
        model.requestScreenRecording()
      }
    }

    Divider()

    Button("Run private-API diagnostics") { model.runDiagnostics() }
    Button("Dump switchability") { model.dumpSwitchability() }
    Button("Test HW capture (off-Space)") { model.runCaptureDiagnostics() }
    if let diagnostics = model.diagnostics {
      Text(diagnostics).font(.caption).textSelection(.enabled)
    }

    Divider()

    Button("Quit ZenTab") { NSApplication.shared.terminate(nil) }
      .keyboardShortcut("q")
  }

  /// A short reminder of the hold chord for the active profile. (The behavior is
  /// fixed; only the trigger keys differ between profiles — see VISION.)
  private var shortcutHint: String {
    switch model.profile {
    case .production:
      return "hold ⌘ then ⇥ (other apps) or ` (this app); ⌥⇥ for everything"
    case .development:
      return "hold ⌃⌥ then Tab (other apps) or ` (this app); A for everything"
    }
  }
}
