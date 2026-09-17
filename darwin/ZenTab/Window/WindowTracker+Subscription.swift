import ApplicationServices
import Foundation

/// App-level AX subscription with retry. Split from `WindowTracker.swift` to keep the
/// tracker within the file-length budget.
extension WindowTracker {
  /// Retry budget for an app that isn't answering AX yet: backoff from 250ms up to 5s
  /// per attempt, ~80s in total — enough for a JVM IDE to bring its UI up. Past that,
  /// the next activation of the app starts a fresh round.
  private static let maxSubscribeAttempts = 20

  /// Subscribe + seed off-main (an unresponsive app must never stall us). An app that
  /// is still launching — a JVM IDE like DevEco/IntelliJ, an Electron app — answers AX
  /// with `.cannotComplete` until its UI is up, and a subscription that fails then
  /// never delivers `kAXWindowCreated`, so its windows would never appear. Retry with
  /// backoff until the subscription takes.
  func subscribe(_ record: AppObservation, attempt: Int = 1) {
    guard !record.subscribed, !record.subscribing, let observer = record.observer else { return }
    record.subscribing = true
    let pid = record.pid
    let identity = ObjectIdentifier(record)
    let appBox = AXElementBox(element: record.appElement)
    let observerBox = AXObserverBox(observer: observer)
    seedQueue.async { [weak self] in
      let ready = self?.subscribeAndSeed(pid: pid, app: appBox, observer: observerBox) ?? false
      DispatchQueue.main.async {
        self?.subscriptionFinished(pid: pid, identity: identity, ready: ready, attempt: attempt)
      }
    }
  }

  private func subscriptionFinished(
    pid: pid_t, identity: ObjectIdentifier, ready: Bool, attempt: Int
  ) {
    // Ignore a stale result for an app that has since quit (or a reused pid).
    guard let record = registry.app(for: pid), ObjectIdentifier(record) == identity else { return }
    record.subscribing = false
    if ready {
      record.subscribed = true
      return
    }
    guard attempt < Self.maxSubscribeAttempts else { return }
    let delay = min(0.25 * pow(2, Double(attempt - 1)), 5)
    record.subscribing = true  // hold the slot through the backoff wait
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
      MainActor.assumeIsolated {
        guard let self, let record = self.registry.app(for: pid),
          ObjectIdentifier(record) == identity
        else { return }
        record.subscribing = false
        self.subscribe(record, attempt: attempt + 1)
      }
    }
  }

  // MARK: - Subscription (seed queue)

  /// Subscribe the app element to the lifecycle notifications, then seed its existing
  /// windows (attribute list for the current Space + brute-force for other Spaces).
  /// Returns false when the app isn't answering AX yet (retry later); the first
  /// notification is the readiness probe, so nothing is seeded against a half-up app.
  private nonisolated func subscribeAndSeed(
    pid: pid_t, app: AXElementBox, observer: AXObserverBox
  ) -> Bool {
    var ready = false
    for notification in Self.appNotifications {
      let result = AXObserverAddNotification(
        observer.observer, app.element, notification as CFString, packRefcon(pid))
      if !ready {
        guard Self.subscriptionSettled(result) else { return false }
        ready = true
      }
    }
    seedWindows(pid: pid, app: app, bruteForce: true)
    return true
  }

  /// Whether an `AXObserverAddNotification` result is final. Success (or already
  /// registered) is done, and so is unsupported / not-implemented — retrying can't
  /// change those. Anything else (`.cannotComplete`, `.failure`, …) is an app that
  /// isn't ready yet.
  private nonisolated static func subscriptionSettled(_ result: AXError) -> Bool {
    switch result {
    case .success, .notificationAlreadyRegistered, .notificationUnsupported, .notImplemented:
      return true
    default:
      return false
    }
  }
}
