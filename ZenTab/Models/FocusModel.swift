import Observation

/// The small amount of state behind ZenTab's main window.
///
/// It is deliberately free of any SwiftUI / UI dependency (note we import
/// `Observation`, not `SwiftUI`) so that it is trivial to unit-test in
/// isolation. All real behaviour lives here rather than in the view.
@Observable
final class FocusModel {
    /// Number of focus sessions completed during this run.
    private(set) var completedSessions: Int = 0

    /// Records one completed focus session.
    func completeSession() {
        completedSessions += 1
    }

    /// Clears the counter back to zero.
    func reset() {
        completedSessions = 0
    }

    /// A calm, changing message based on how many sessions are done.
    var encouragement: String {
        switch completedSessions {
        case 0: "Take a breath, then begin."
        case 1..<3: "Nicely done — keep the rhythm."
        case 3..<6: "You're in the flow."
        default: "Deep focus. Beautiful work."
        }
    }
}
