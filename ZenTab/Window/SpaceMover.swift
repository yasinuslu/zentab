import AppKit

/// Which way `fling` sends a window off the current Space. Kept here (a Foundation-only
/// value) so the pure `OverlaySession` reducer can carry it without importing AppKit.
/// `away` (↑) means "any adjacent Space", preferring the right then the left.
enum FlingDirection: Equatable {
  case left
  case right
  case away
}

/// Moves another app's window across Mission Control Spaces: the primitive behind summon
/// (bring here) and fling (send to an adjacent Space). Proven in the spike
/// (`docs/space-move-spike-plan.md`): on macOS 26 every window-targeted CGS call is inert,
/// but performing an `SLSBridgedMoveWindowsToManagedSpaceOperation` relocates a *single*
/// window, no SIP, no persistent process assignment, without following it to its new Space.
enum SpaceMover {
  /// Summon: bring `window` to the Space currently visible on the display under the mouse
  /// (the one the overlay is shown on). The destination is always the active Space, so
  /// there is never a Space to pick or create.
  @MainActor
  static func summon(_ window: WindowInfo) {
    guard !window.isWindowlessApp, let uuid = activeDisplayUUID() else { return }
    let destination = CGSManagedDisplayGetCurrentSpace(cgsConnection, uuid as CFString)
    performBridgedMove(window.windowID, destination)
  }

  /// Fling: send `window` off the current Space to an adjacent user Space. `left`/`right`
  /// pick that neighbor; `away` takes the right neighbor, or the left if there is no right.
  /// A no-op at the edge — ZenTab never creates a Space. Returns whether a move was issued
  /// (so the caller can avoid dropping the tile when nothing actually moved).
  @MainActor
  @discardableResult
  static func fling(_ window: WindowInfo, _ direction: FlingDirection) -> Bool {
    guard !window.isWindowlessApp, let uuid = activeDisplayUUID() else { return false }
    let current = CGSManagedDisplayGetCurrentSpace(cgsConnection, uuid as CFString)
    let spaces = userSpaces(containing: current)
    guard let index = spaces.firstIndex(of: current) else { return false }
    let candidates: [Int]
    switch direction {
    case .left: candidates = [index - 1]
    case .right: candidates = [index + 1]
    case .away: candidates = [index + 1, index - 1]  // prefer right, fall back to left
    }
    guard let neighbor = candidates.first(where: { spaces.indices.contains($0) }) else {
      return false  // edge: no adjacent Space exists, and we never create one
    }
    performBridgedMove(window.windowID, spaces[neighbor])
    return true
  }

  /// The window ids the WindowServer composites on the active display's current Space —
  /// i.e. the windows that are "here". The overlay uses this to split its list into the
  /// ELSEWHERE grid and the HERE strip. Empty if the Space can't be resolved.
  @MainActor
  static func windowsOnCurrentSpace() -> Set<CGWindowID> {
    guard let uuid = activeDisplayUUID() else { return [] }
    let current = CGSManagedDisplayGetCurrentSpace(cgsConnection, uuid as CFString)
    var setTags: UInt64 = 0
    var clearTags: UInt64 = 0
    guard
      let array = SLSCopyWindowsWithOptionsAndTags(
        cgsConnection, 0, [NSNumber(value: current)] as CFArray, 0x7, &setTags, &clearTags
      )?.takeRetainedValue() as? [NSNumber]
    else { return [] }
    return Set(array.map { $0.uint32Value })
  }

  // MARK: - The proven move (bridged WindowServer operation)

  // RTLD_DEFAULT (-2) resolves objc_msgSend from the already-linked libobjc. Resolved once;
  // an immutable function pointer, hence safe to share across actors.
  nonisolated(unsafe) private static let msgSend =
    dlsym(UnsafeMutableRawPointer(bitPattern: -2), "objc_msgSend")

  /// Build `SLSBridgedMoveWindowsToManagedSpaceOperation(initWithWindows:spaceID:)` and
  /// perform it in-process via the zero-argument `performWithWMBridgeDelegate` method.
  private static func performBridgedMove(_ windowID: CGWindowID, _ space: CGSSpaceID) {
    guard let cls = NSClassFromString("SLSBridgedMoveWindowsToManagedSpaceOperation"),
      let msgSend
    else { return }
    typealias MsgObj = @convention(c) (UnsafeRawPointer?, Selector) -> UnsafeRawPointer?
    typealias MsgInit = @convention(c) (
      UnsafeRawPointer?, Selector, UnsafeRawPointer?, UInt64
    ) -> UnsafeRawPointer?
    let msgObj = unsafeBitCast(msgSend, to: MsgObj.self)
    let msgInit = unsafeBitCast(msgSend, to: MsgInit.self)
    let classPtr = unsafeBitCast(cls, to: UnsafeRawPointer.self)

    let windows = [NSNumber(value: windowID)] as NSArray
    withExtendedLifetime(windows) {
      guard let allocated = msgObj(classPtr, NSSelectorFromString("alloc")) else { return }
      let windowsPtr = Unmanaged.passUnretained(windows).toOpaque()
      guard
        let operation = msgInit(allocated, NSSelectorFromString("initWithWindows:spaceID:"), windowsPtr, space)
      else { return }
      _ = msgObj(operation, NSSelectorFromString("performWithWMBridgeDelegate"))
      _ = msgObj(operation, NSSelectorFromString("release"))
    }
  }

  // MARK: - Space geometry

  /// The display UUID for the screen under the mouse (where the overlay is shown), so
  /// "current Space" and Space adjacency are read for the display the user is looking at.
  @MainActor
  private static func activeDisplayUUID() -> String? {
    let mouse = NSEvent.mouseLocation
    let screen =
      NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
      ?? NSScreen.main ?? NSScreen.screens.first
    return screen?.spaceUUID()
  }

  /// The ordered **user** Space ids on the display whose Spaces include `space` (fullscreen
  /// and system Spaces are excluded, so a fling never lands a window in a fullscreen app).
  private static func userSpaces(containing space: CGSSpaceID) -> [CGSSpaceID] {
    let displays = (CGSCopyManagedDisplaySpaces(cgsConnection) as? [NSDictionary]) ?? []
    for display in displays {
      let spaceDicts = (display["Spaces"] as? [NSDictionary]) ?? []
      let allIDs = spaceDicts.compactMap { $0["id64"] as? CGSSpaceID }
      guard allIDs.contains(space) else { continue }
      return spaceDicts.filter { ($0["type"] as? Int) == 0 }.compactMap { $0["id64"] as? CGSSpaceID }
    }
    return []
  }
}
