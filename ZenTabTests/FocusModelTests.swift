import Testing
@testable import ZenTab

/// Unit tests for ``FocusModel`` written with Swift Testing (`import Testing`),
/// the modern default in Xcode 16+. Run them with ⌘U in Xcode, or `bin/test`.
@Suite("FocusModel")
struct FocusModelTests {

    @Test("Starts empty with the opening message")
    func startsEmpty() {
        let model = FocusModel()
        #expect(model.completedSessions == 0)
        #expect(model.encouragement == "Take a breath, then begin.")
    }

    @Test("Completing a session increments the count")
    func completeIncrements() {
        let model = FocusModel()

        model.completeSession()
        #expect(model.completedSessions == 1)

        model.completeSession()
        #expect(model.completedSessions == 2)
    }

    @Test("Reset returns the count to zero")
    func resetClears() {
        let model = FocusModel()
        model.completeSession()
        model.completeSession()

        model.reset()
        #expect(model.completedSessions == 0)
    }

    @Test("Encouragement changes as sessions accumulate", arguments: [
        (0, "Take a breath, then begin."),
        (1, "Nicely done, keep the rhythm."),
        (3, "You're in the flow."),
        (6, "Deep focus. Beautiful work."),
    ])
    func encouragementThresholds(count: Int, expected: String) {
        let model = FocusModel()
        for _ in 0..<count { model.completeSession() }
        #expect(model.encouragement == expected)
    }
}
