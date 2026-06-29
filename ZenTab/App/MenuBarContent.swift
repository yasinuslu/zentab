import SwiftUI

/// The menu bar dropdown. Non-hot UI, so SwiftUI is the right tool here. It shows
/// permission state, the actions to grant them, a private-API diagnostics smoke
/// test, and Quit.
struct MenuBarContent: View {
  @ObservedObject var model: AppModel

  var body: some View {
    if model.accessibilityTrusted {
      Text(model.switcherRunning ? "ZenTab is running" : "Starting…")
      Text("Hold ⌃⌥ and press Tab to switch windows")
        .font(.caption)
    } else {
      Text("Accessibility permission required")
      Button("Grant Accessibility…") { model.requestAccessibility() }
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
    if let diagnostics = model.diagnostics {
      Text(diagnostics).font(.caption).textSelection(.enabled)
    }

    Divider()

    Button("Quit ZenTab") { NSApplication.shared.terminate(nil) }
      .keyboardShortcut("q")
  }
}
