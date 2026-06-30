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
    ZenTabApp.main()
  }
}
