import SwiftUI

/// The single screen of ZenTab.
///
/// It owns a ``FocusModel`` and reflects its state. Keep view code declarative
/// and push any real logic down into the model so it stays easy to test.
struct ContentView: View {
    @State private var model = FocusModel()

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "circle.hexagongrid")
                .font(.system(size: 56, weight: .ultraLight))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("ZenTab")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                Text(model.encouragement)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 4) {
                Text("\(model.completedSessions)")
                    .font(.system(size: 64, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(model.completedSessions == 1 ? "session" : "sessions")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .animation(.snappy, value: model.completedSessions)

            HStack(spacing: 12) {
                Button {
                    model.completeSession()
                } label: {
                    Label("Complete a session", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

                Button {
                    model.reset()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .controlSize(.large)
                .disabled(model.completedSessions == 0)
            }

            Spacer()
        }
        .padding(40)
        .frame(minWidth: 380, minHeight: 480)
    }
}

#Preview {
    ContentView()
}
