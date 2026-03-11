import SwiftUI

struct MicrophoneButton: View {
    let isRecording: Bool
    let isPaused: Bool
    let audioLevel: Float
    let action: () -> Void

    init(isRecording: Bool, isPaused: Bool = false, audioLevel: Float, action: @escaping () -> Void) {
        self.isRecording = isRecording
        self.isPaused = isPaused
        self.audioLevel = audioLevel
        self.action = action
    }

    private var ringScale: CGFloat {
        isRecording && !isPaused ? 1.0 + CGFloat(audioLevel) * 0.3 : 1.0
    }

    private var buttonColor: Color {
        if isPaused { return .orange }
        if isRecording { return .red }
        return .accentColor
    }

    private var ringColor: Color {
        if isPaused { return .orange.opacity(0.3) }
        if isRecording { return .red.opacity(0.3) }
        return .accentColor.opacity(0.2)
    }

    private var iconName: String {
        if isPaused { return "stop.fill" }
        if isRecording { return "stop.fill" }
        return "mic.fill"
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                // Animated ring
                Circle()
                    .stroke(ringColor, lineWidth: 4)
                    .frame(width: 100, height: 100)
                    .scaleEffect(ringScale)
                    .animation(isPaused ? nil : .easeOut(duration: 0.1), value: audioLevel)

                // Main circle
                Circle()
                    .fill(buttonColor)
                    .frame(width: 80, height: 80)

                // Icon
                Image(systemName: iconName)
                    .font(.system(size: 30))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact, trigger: isRecording)
    }
}
