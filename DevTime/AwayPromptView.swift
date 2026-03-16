import SwiftUI

struct AwayPromptView: View {
    @ObservedObject var timer: TimerManager

    var body: some View {
        VStack(spacing: 16) {
            Text("\u{1F4A4} Welcome Back!")
                .font(.title2.bold())

            Text("You were away for \(formatDuration(timer.awayDuration))")
                .font(.body)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("Keep Time") {
                    timer.keepAwayTime()
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)

                Button("Discard") {
                    timer.discardAwayTime()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }

            Text("Keep if you were in a meeting.\nDiscard if you stepped away.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(width: 300)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        if h > 0 {
            return "\(h)h \(m)m"
        }
        return "\(m)m"
    }
}
