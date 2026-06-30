import AppKit

/// Dev-only entry points for the cross-Space move feasibility spike
/// (`docs/space-move-spike-plan.md`). The one question: can ZenTab move *another
/// process's* window to a different Mission Control Space on macOS 26, from a normal
/// app, without SIP — verified by test, not argued.
///
/// Neither path here touches the shortcut/capture/menu-bar layer: they are reached only
/// via the `--space-move-helper` / `--space-move-selftest` launch args, dispatched in
/// `ZenTabMain` *before* the normal SwiftUI app (and thus `AppModel.bootstrap`) runs.
/// Both are guarded, return `Never`, and clean up after themselves (no orphans).
enum SpaceMoveSpike {

  // MARK: - Helper (child) mode  ── `--space-move-helper`

  /// A throwaway target in a *separate process* (its own WindowServer connection), so
  /// the spike tests the real "move ANOTHER app's window" case rather than its own.
  /// Opens *two* plain standard windows in one process and prints their `CGWindowID`s as
  /// `WID <a>` and `WIDB <b>` — two windows so the self-test can prove single-window
  /// precision (move A, B stays). Idles until killed or its parent (the self-test) dies.
  static func runHelper() -> Never {
    MainActor.assumeIsolated {  // we are on the process's main thread at entry
      let app = NSApplication.shared
      app.setActivationPolicy(.regular)

      func makeWindow(_ title: String, x: CGFloat) -> NSWindow {
        let window = NSWindow(
          contentRect: NSRect(x: x, y: 240, width: 380, height: 260),
          styleMask: [.titled, .closable, .miniaturizable, .resizable],
          backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        return window
      }
      let windowA = makeWindow("ZenTab Space-Move Helper A", x: 220)
      let windowB = makeWindow("ZenTab Space-Move Helper B", x: 640)
      app.activate(ignoringOtherApps: true)

      // `windowNumber` is the CGWindowID; assigned once the window is ordered on screen.
      // Nudge the run loop once if the server hasn't handed it back yet.
      if windowA.windowNumber <= 0 || windowB.windowNumber <= 0 {
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
      }
      print("WID \(CGWindowID(max(0, windowA.windowNumber)))")
      print("WIDB \(CGWindowID(max(0, windowB.windowNumber)))")
      fflush(stdout)

      // No orphans: exit if the parent dies (reparented to launchd ⇒ ppid 1), and hard-
      // cap our lifetime so a crashed self-test can never leave us running.
      let started = Date()
      Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
        if getppid() == 1 || Date().timeIntervalSince(started) > 180 { exit(0) }
      }
      app.run()
    }
    exit(0)
  }

  // MARK: - Self-test (ladder) mode  ── `--space-move-selftest`

  /// Run the whole strategy ladder against the helper in one process, write a result
  /// table to `~/zentab-spacemove.txt`, and exit:
  ///   0 = GREEN (≥1 strategy moved the helper both directions),
  ///   1 = RED   (the whole ladder failed),
  ///   2 = SKIP  (precondition unmet: <2 Desktops, or the helper couldn't launch).
  /// A nonzero exit other than 1/2 means a strategy crashed the process — the report on
  /// disk ends at a `BEGIN <strategy>` marker that names the culprit.
  static func runSelfTest() -> Never {
    let outcome = SpaceMoveSelfTest().run()
    FileHandle.standardError.write(Data("space-move-selftest: \(outcome.verdict)\n".utf8))
    exit(outcome.exitCode)
  }
}

/// libobjc runtime, for building + performing the bridged-operation object directly.
@_silgen_name("objc_getClass") private func zt_objc_getClass(_ name: UnsafePointer<CChar>) -> UnsafeRawPointer?
@_silgen_name("sel_registerName") private func zt_sel_registerName(_ name: UnsafePointer<CChar>) -> UnsafeRawPointer?

/// The oracle + ladder. Pure synchronous CGS IPC on the calling thread — no run loop,
/// no NSApplication, so it never becomes a GUI app or perturbs anything global.
private final class SpaceMoveSelfTest {
  private let cid = CGSMainConnectionID()
  private let reportPath = (NSHomeDirectory() as NSString).appendingPathComponent("zentab-spacemove.txt")
  private var log = ""

  /// `true` once the settle phase confirms `CGSCopySpacesForWindows` actually reports the
  /// helper window's Space (so we can trust it as the primary oracle below).
  private var cgsReadWorks = false

  struct Outcome {
    let verdict: String
    let exitCode: Int32
  }

  func run() -> Outcome {
    line("# ZenTab cross-Space move self-test")
    line("# \(ProcessInfo.processInfo.operatingSystemVersionString)")
    line("# WindowServer connection: \(cid)")
    line("")

    // 1. Launch the helper child and read its window id.
    guard let helper = launchHelper() else {
      line("ABORT: could not launch helper child / read its window id.")
      return finish(verdict: "ABORT (helper)", code: 2)
    }
    defer { helper.terminate() }  // no orphans, on every exit path
    let wid = helper.wid
    let helperPID = helper.process.processIdentifier
    line("helper: pid=\(helperPID) wid=\(wid)")

    // 2. Resolve Spaces. Precondition: ≥2 Desktops on the helper window's display.
    guard let display = mainDisplayUUID() else {
      line("ABORT: no main display UUID.")
      return finish(verdict: "ABORT (display)", code: 2)
    }
    let s1 = CGSManagedDisplayGetCurrentSpace(cid, display)
    let displaySpaces = spacesOnDisplay(containing: s1)
    line("current Space S1=\(s1); Spaces on its display=\(displaySpaces)")

    // 3. Settle: wait for the window to register, so an early empty read can't masquerade
    //    as a failed move. Confirms whether CGSCopySpacesForWindows is a trustworthy oracle.
    settle(wid: wid, expectedSpace: s1)

    guard let s2 = displaySpaces.first(where: { $0 != s1 }) else {
      line("")
      line("SKIP: only one Desktop on this display. The oracle needs a second Space to")
      line("move into. Create one (Mission Control ▸ +) and rerun. It never creates one.")
      return finish(verdict: "SKIP (need a 2nd Desktop)", code: 2)
    }
    line("destination Space S2=\(s2)")
    line("")
    line("# ladder — each strategy: FLING home→away (to a non-current Space), then")
    line("# SUMMON away→home (back to the current Space). Both must verify by Space id;")
    line("# on-screen presence is logged as an independent cross-check.")
    line("")

    // 4. Run the ladder. Record every row; first clean GREEN wins.
    var greens: [String] = []
    var cleanGreens: [String] = []
    for strategy in strategies(helperPID: helperPID, display: display) {
      // BEGIN marker is flushed BEFORE the move, so an ABI crash names the culprit on disk.
      line("BEGIN \(strategy.name)")
      flush()
      let result = evaluate(strategy, wid: wid, s1: s1, s2: s2, display: display)
      // Replace the BEGIN line with the finished row.
      log = String(log.dropLast("BEGIN \(strategy.name)\n".count))
      line(result.row)
      flush()
      if result.green {
        greens.append(strategy.name)
        if result.clean { cleanGreens.append(strategy.name) }
      }
    }
    line("")

    // 5. Single-window precision: prove the per-window winner moves ONE window (B stays),
    //    and contrast it with the process-level call (which drags every window).
    precisionTest(widA: wid, widB: helper.widB, s1: s1, s2: s2, helperPID: helperPID, display: display)
    line("")

    // Leave the helper windows back on S1 so nothing is stranded on a hidden Space.
    restoreToS1(wid, s1: s1, display: display)

    if !cleanGreens.isEmpty {
      return finish(verdict: "GREEN (clean): \(cleanGreens.joined(separator: ", "))", code: 0)
    }
    if !greens.isEmpty {
      return finish(
        verdict: "GREEN (degraded, forces a Space switch): \(greens.joined(separator: ", "))", code: 0)
    }
    line("RED: no strategy moved the helper window both directions.")
    return finish(verdict: "RED", code: 1)
  }

  private func finish(verdict: String, code: Int32) -> Outcome {
    line(verdict)
    flush()
    return Outcome(verdict: verdict, exitCode: code)
  }

  /// Prove granularity: the bridged op moves exactly window A (B stays on S1), whereas
  /// `SLSProcessAssignToSpace` drags every window of the process. This is the difference
  /// that decides whether summon/fling can target a single window.
  private func precisionTest(
    widA: CGWindowID, widB: CGWindowID, s1: CGSSpaceID, s2: CGSSpaceID, helperPID: pid_t,
    display: CFString
  ) {
    guard widB != 0 else {
      line("precision: SKIPPED (second helper window id unavailable)")
      return
    }
    line("# single-window precision (A=\(widA) B=\(widB), both start on current S1=\(s1)):")

    // Reliable setup via the per-window bridged op (the plain CGS moves are inert here).
    Self.performBridgedMove(wid: widA, to: s1)
    Self.performBridgedMove(wid: widB, to: s1)
    _ = poll { self.windowsOn(s1).contains(widA) && self.windowsOn(s1).contains(widB) }

    // (a) BRIDGED: move ONLY A to S2; B must stay on S1.
    Self.performBridgedMove(wid: widA, to: s2)
    _ = poll { self.windowsOn(s2).contains(widA) }
    let aOnS2 = windowsOn(s2).contains(widA)
    let bStayed = windowsOn(s1).contains(widB) && !windowsOn(s2).contains(widB)
    line(
      "  bridged  move A→S2: A_on_S2=\(aOnS2) B_stayed_S1=\(bStayed)"
        + " → \((aOnS2 && bStayed) ? "PER-WINDOW ✓ (only A moved)" : "NOT per-window ✗")")
    Self.performBridgedMove(wid: widA, to: s1)  // restore A
    _ = poll { self.windowsOn(s1).contains(widA) }

    // (b) PROCESS-ASSIGN contrast: assigning the process should drag BOTH windows.
    SLSProcessAssignToSpace(cid, helperPID, s2)
    _ = poll { self.windowsOn(s2).contains(widA) && self.windowsOn(s2).contains(widB) }
    let aMoved = windowsOn(s2).contains(widA)
    let bMoved = windowsOn(s2).contains(widB)
    line(
      "  process  assign→S2: A_on_S2=\(aMoved) B_on_S2=\(bMoved)"
        + " → \((aMoved && bMoved) ? "PER-PROCESS (drags all windows)" : "partial \(aMoved)/\(bMoved)")")
    // Restore both to S1.
    SLSProcessAssignToSpace(cid, helperPID, s1)
    Self.performBridgedMove(wid: widA, to: s1)
    Self.performBridgedMove(wid: widB, to: s1)
    _ = poll { self.windowsOn(s1).contains(widA) && self.windowsOn(s1).contains(widB) }
  }

  // MARK: Settle

  private func settle(wid: CGWindowID, expectedSpace: CGSSpaceID) {
    let started = Date()
    var spaces = spacesFor(wid)
    var onScreen = isOnScreen(wid)
    while Date().timeIntervalSince(started) < 2, spaces.isEmpty, !onScreen {
      usleep(40_000)
      spaces = spacesFor(wid)
      onScreen = isOnScreen(wid)
    }
    cgsReadWorks = !spaces.isEmpty
    let ms = Int(Date().timeIntervalSince(started) * 1000)
    line(
      "settle (\(ms)ms): helper window cgs-spaces=\(spaces) onScreen=\(onScreen) "
        + "(expected Space \(expectedSpace)); cgs oracle \(cgsReadWorks ? "TRUSTED" : "UNRELIABLE → using on-screen")")
  }

  // MARK: Helper launch

  private struct Helper {
    let process: Process
    let wid: CGWindowID  // window A
    let widB: CGWindowID  // window B (for the single-window precision test)
    func terminate() { if process.isRunning { process.terminate() } }
  }

  /// Re-exec this same binary with `--space-move-helper`, capture its stdout, and read the
  /// `WID <a>` and `WIDB <b>` lines (≤5 s). Returns nil on launch failure or timeout.
  private func launchHelper() -> Helper? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    process.arguments = ["--space-move-helper"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do { try process.run() } catch { return nil }

    final class Box: @unchecked Sendable {
      var a: CGWindowID?
      var b: CGWindowID?
    }
    let box = Box()
    let semaphore = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
      var buffer = Data()
      let handle = pipe.fileHandleForReading
      while true {
        let chunk = handle.availableData
        if chunk.isEmpty { break }  // EOF
        buffer.append(chunk)
        if let text = String(data: buffer, encoding: .utf8) {
          box.a = Self.parseWID(text, prefix: "WID ")
          box.b = Self.parseWID(text, prefix: "WIDB ")
          if box.a != nil, box.b != nil { break }
        }
      }
      semaphore.signal()
    }
    if semaphore.wait(timeout: .now() + 5) == .timedOut || box.a == nil {
      process.terminate()
      return nil
    }
    return Helper(process: process, wid: box.a!, widB: box.b ?? 0)
  }

  private static func parseWID(_ text: String, prefix: String) -> CGWindowID? {
    for raw in text.split(separator: "\n") where raw.hasPrefix(prefix) {
      if let value = UInt32(raw.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)) {
        return value
      }
    }
    return nil
  }

  // MARK: Strategy ladder

  private struct Strategy {
    let name: String
    /// Perform the move of `wid` from Space `from` to Space `to`.
    let move: (CGWindowID, CGSSpaceID, CGSSpaceID) -> Void
  }

  private func strategies(helperPID: pid_t, display: CFString) -> [Strategy] {
    let cid = self.cid
    return [
      // ── window-targeted CGS calls (alt-tab's set; expected inert on macOS ≥15) ──
      Strategy(name: "1·CGSMoveWindowsToManagedSpace") { wid, _, to in
        CGSMoveWindowsToManagedSpace(cid, [wid] as CFArray, to)
      },
      Strategy(name: "2·CGSAdd+RemoveWindowsFromSpaces") { wid, from, to in
        CGSAddWindowsToSpaces(cid, [wid] as CFArray, [to] as CFArray)
        CGSRemoveWindowsFromSpaces(cid, [wid] as CFArray, [from] as CFArray)
      },
      Strategy(name: "3·Front-then-CGSMove") { wid, _, to in
        var psn = ProcessSerialNumber()
        if zt_GetProcessForPID(helperPID, &psn) == noErr {
          _SLPSSetFrontProcessWithOptions(&psn, wid, SLPSMode.userGenerated.rawValue)
        }
        CGSMoveWindowsToManagedSpace(cid, [wid] as CFArray, to)
      },
      Strategy(name: "4·SetCurrentSpace-dance") { wid, from, to in
        CGSManagedDisplaySetCurrentSpace(cid, display, to)
        CGSMoveWindowsToManagedSpace(cid, [wid] as CFArray, to)
        CGSManagedDisplaySetCurrentSpace(cid, display, from)
      },
      Strategy(name: "5·CGSSpaceAddWindowsAndRemove") { wid, _, to in
        CGSSpaceAddWindowsAndRemoveFromSpaces(cid, to, [wid] as CFArray, 0x8_0007)
      },
      Strategy(name: "6·CGSMoveWorkspaceWindowList") { wid, _, to in
        CGSMoveWorkspaceWindowList(cid, [wid] as CFArray, 1, to)
      },
      // ── yabai's actual no-SIP paths ──
      Strategy(name: "7·CompatID-dance(yabai)") { wid, _, to in
        var id = wid
        SLSSpaceSetCompatID(cid, to, 0x7961_6265)
        SLSSetWindowListWorkspace(cid, &id, 1, 0x7961_6265)
        SLSSpaceSetCompatID(cid, to, 0x0)
      },
      Strategy(name: "8·SLSProcessAssignToSpace") { _, _, to in
        SLSProcessAssignToSpace(cid, helperPID, to)
      },
      Strategy(name: "9·AssignToAllSpaces+ToSpace") { _, _, to in
        SLSProcessAssignToAllSpaces(cid, helperPID)
        SLSProcessAssignToSpace(cid, helperPID, to)
      },
      Strategy(name: "10·SLSMoveWindowsToManagedSpace") { wid, _, to in
        SLSMoveWindowsToManagedSpace(cid, [wid] as CFArray, to)
      },
      // ── the modern *per-window* bridged operation: build the operation object via the
      //    ObjC runtime and perform it directly (`performWithWMBridgeDelegate`, zero-arg —
      //    no hidden C dispatcher / Mach-O scan needed). This is the clean single-window
      //    path. ABI-touches the ObjC runtime, so it runs last (earlier rows are flushed).
      Strategy(name: "11·Bridged-performWithWMBridgeDelegate") { wid, _, to in
        Self.performBridgedMove(wid: wid, to: to)
      },
    ]
  }

  /// Build `SLSBridgedMoveWindowsToManagedSpaceOperation(initWithWindows:spaceID:)` and
  /// perform it in-process via the zero-arg `performWithWMBridgeDelegate` ObjC method.
  /// Single-window precision, no SIP, no persistent process assignment.
  private static func performBridgedMove(wid: CGWindowID, to space: CGSSpaceID) {
    guard let cls = zt_objc_getClass("SLSBridgedMoveWindowsToManagedSpaceOperation"),
      let handle = dlopen(nil, RTLD_LAZY),
      let msgSendRaw = dlsym(handle, "objc_msgSend")
    else { return }
    typealias MsgObj = @convention(c) (UnsafeRawPointer?, UnsafeRawPointer?) -> UnsafeRawPointer?
    typealias MsgInit = @convention(c) (
      UnsafeRawPointer?, UnsafeRawPointer?, UnsafeRawPointer?, UInt64
    ) -> UnsafeRawPointer?
    let msgObj = unsafeBitCast(msgSendRaw, to: MsgObj.self)
    let msgInit = unsafeBitCast(msgSendRaw, to: MsgInit.self)

    let windows = [NSNumber(value: wid)] as NSArray
    withExtendedLifetime(windows) {
      guard let alloced = msgObj(cls, zt_sel_registerName("alloc")) else { return }
      let windowsPtr = Unmanaged.passUnretained(windows).toOpaque()
      guard
        let op = msgInit(alloced, zt_sel_registerName("initWithWindows:spaceID:"), windowsPtr, space)
      else { return }
      _ = msgObj(op, zt_sel_registerName("performWithWMBridgeDelegate"))
      _ = msgObj(op, zt_sel_registerName("release"))
    }
  }

  private struct Eval {
    let row: String
    let green: Bool
    let clean: Bool
  }

  /// Drive one strategy through a genuine round trip and verify by Space id (primary) and
  /// on-screen presence (independent cross-check).
  private func evaluate(
    _ strategy: Strategy, wid: CGWindowID, s1: CGSSpaceID, s2: CGSSpaceID, display: CFString
  ) -> Eval {
    restoreToS1(wid, s1: s1, display: display)  // clean slate
    let home = spacesFor(wid).first ?? s1
    let away = (home == s2) ? s1 : s2  // never a no-op self-move

    let curBefore = CGSManagedDisplayGetCurrentSpace(cid, display)

    // FLING: home → away (a non-current Space).
    strategy.move(wid, home, away)
    let fling = verify(wid: wid, dest: away, display: display)

    guard fling.ok else {
      let curAfter = CGSManagedDisplayGetCurrentSpace(cid, display)
      let switchNote = curBefore != curAfter ? " curSpace \(curBefore)→\(curAfter)" : ""
      return Eval(
        row: "[\(strategy.name)] RED   fling \(home)→\(away) failed [\(fling.detail)]\(switchNote)",
        green: false, clean: false)
    }

    // SUMMON: away → home (back to the current Space) — the curation primitive.
    let nowOn = spacesFor(wid).first ?? away
    strategy.move(wid, nowOn, home)
    let summon = verify(wid: wid, dest: home, display: display)

    let curAfter = CGSManagedDisplayGetCurrentSpace(cid, display)
    let switched = curBefore != curAfter
    let green = fling.ok && summon.ok
    let clean = green && !switched
    let switchNote = switched ? " ⚠︎ forced Space switch \(curBefore)→\(curAfter)" : " clean"
    let verdict = green ? (clean ? "GREEN " : "GREEN*") : "PARTIAL"
    return Eval(
      row: "[\(strategy.name)] \(verdict) fling \(home)→\(away) [\(fling.detail)]"
        + " · summon \(away)→\(home) [\(summon.detail)]\(switchNote)",
      green: green, clean: clean)
  }

  /// Verify a move *actually* landed `wid` on `dest`, using three signals:
  ///  • `destList` — is the window in the WindowServer's composited list for `dest`? (authoritative)
  ///  • `cgs`      — the Space-id membership read.
  ///  • `onScr`    — on-screen presence (≈ on the current Space).
  /// A real move means the window enters `dest`'s list AND, when `dest` isn't the current
  /// Space, leaves the current Space's list (i.e. it truly relocated, not went sticky/both).
  private func verify(wid: CGWindowID, dest: CGSSpaceID, display: CFString) -> (ok: Bool, detail: String) {
    let current = CGSManagedDisplayGetCurrentSpace(cid, display)
    let landed = poll {
      self.windowsOn(dest).contains(wid) && (dest == current || !self.windowsOn(current).contains(wid))
    }
    let onDest = windowsOn(dest).contains(wid)
    let onCur = windowsOn(current).contains(wid)
    let spaces = spacesFor(wid)
    let onScreen = isOnScreen(wid)
    let detail =
      "destList=\(onDest) curList=\(onCur) cgs=\(spaces) onScr=\(onScreen)"
    return (landed, detail)
  }

  /// The window ids the WindowServer composites on `space` (authoritative per-Space list).
  private func windowsOn(_ space: CGSSpaceID) -> [CGWindowID] {
    var setTags: UInt64 = 0
    var clearTags: UInt64 = 0
    guard
      let array = SLSCopyWindowsWithOptionsAndTags(
        cid, 0, [NSNumber(value: space)] as CFArray, 0x7, &setTags, &clearTags
      )?.takeRetainedValue() as? [NSNumber]
    else { return [] }
    return array.map { $0.uint32Value }
  }

  // MARK: Space reads + restore

  /// Best-effort return of the window to S1 between strategies (and at the end).
  private func restoreToS1(_ wid: CGWindowID, s1: CGSSpaceID, display: CFString) {
    if spacesFor(wid).contains(s1) { return }
    CGSMoveWindowsToManagedSpace(cid, [wid] as CFArray, s1)
    if poll(timeoutMs: 400, { self.spacesFor(wid).contains(s1) }) { return }
    var id = wid
    SLSSpaceSetCompatID(cid, s1, 0x7961_6265)
    SLSSetWindowListWorkspace(cid, &id, 1, 0x7961_6265)
    SLSSpaceSetCompatID(cid, s1, 0x0)
    _ = poll(timeoutMs: 400, { self.spacesFor(wid).contains(s1) })
  }

  /// The Space ids a window currently lives on (the oracle's ground truth).
  private func spacesFor(_ wid: CGWindowID) -> [CGSSpaceID] {
    (CGSCopySpacesForWindows(cid, CGSSpaceMask.all.rawValue, [wid] as CFArray) as? [CGSSpaceID]) ?? []
  }

  /// Independent oracle: is the window in the on-screen list (≈ on the current Space)?
  private func isOnScreen(_ wid: CGWindowID) -> Bool {
    guard
      let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
    else { return false }
    return list.contains { ($0[kCGWindowNumber as String] as? CGWindowID) == wid }
  }

  /// All Space ids on the display that currently shows `space` (multi-monitor safe).
  private func spacesOnDisplay(containing space: CGSSpaceID) -> [CGSSpaceID] {
    let raw = (CGSCopyManagedDisplaySpaces(cid) as? [NSDictionary]) ?? []
    for screen in raw {
      let ids = ((screen["Spaces"] as? [NSDictionary]) ?? []).compactMap { $0["id64"] as? CGSSpaceID }
      if ids.contains(space) { return ids }
    }
    return raw.flatMap { ($0["Spaces"] as? [NSDictionary] ?? []).compactMap { $0["id64"] as? CGSSpaceID } }
  }

  private func mainDisplayUUID() -> CFString? {
    guard let uuid = CGDisplayCreateUUIDFromDisplayID(CGMainDisplayID())?.takeRetainedValue()
    else { return nil }
    return CFUUIDCreateString(nil, uuid)
  }

  /// Poll a condition (WindowServer moves are async) up to `timeoutMs`, 40 ms cadence.
  private func poll(timeoutMs: Int = 800, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000)
    while Date() < deadline {
      if condition() { return true }
      usleep(40_000)
    }
    return condition()
  }

  private func line(_ text: String) { log += text + "\n" }
  private func flush() { try? log.write(toFile: reportPath, atomically: true, encoding: .utf8) }
}
