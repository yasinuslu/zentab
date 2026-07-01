import AppKit

/// The real process entry point. It exists so a couple of *dev-only* launch args can be
/// intercepted before the normal menu-bar app (and its shortcut/capture layer) ever
/// boots. With no such arg, it hands straight off to the SwiftUI `ZenTabApp`.
///
///   --space-move-helper     open one plain window in a separate process and idle
///   --space-move-selftest   run the cross-Space move ladder, write a report, exit
///
/// Both spike paths live in `SpaceMoveSpike` and return `Never`; see
/// `docs/space-move-spike-plan.md`.
@main
enum ZenTabMain {
  static func main() {
    let arguments = CommandLine.arguments
    if arguments.contains("--space-move-helper") { SpaceMoveSpike.runHelper() }
    if arguments.contains("--space-move-selftest") { SpaceMoveSpike.runSelfTest() }
    if let index = arguments.firstIndex(of: "--render-overlay"), index + 1 < arguments.count {
      OverlayRenderer.run(
        path: arguments[index + 1], board: arguments.contains("--board"), size: Self.parseSize(arguments))
    }
    ZenTabApp.main()
  }

  /// Optional `--size WxH` (logical points) for the overlay renderer, so the responsive scaling
  /// can be checked at a laptop and a big-monitor width. `nil` → the renderer's default.
  private static func parseSize(_ arguments: [String]) -> CGSize? {
    guard let index = arguments.firstIndex(of: "--size"), index + 1 < arguments.count else { return nil }
    let parts = arguments[index + 1].lowercased().split(separator: "x")
    guard parts.count == 2, let width = Double(parts[0]), let height = Double(parts[1]), width > 0, height > 0
    else { return nil }
    return CGSize(width: width, height: height)
  }
}
