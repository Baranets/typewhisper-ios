#if canImport(ActivityKit)
import ActivityKit
import SwiftUI
import WidgetKit

struct RecordingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            // Lock Screen presentation
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "mic.fill")
                        .font(.title2)
                        .foregroundStyle(context.state.isRecording ? .red : .orange)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(formatDuration(context.state.duration))
                        .font(.title2)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                DynamicIslandExpandedRegion(.trailing) {
                    HStack(spacing: 12) {
                        Button(intent: TogglePauseLiveActivityIntent()) {
                            Image(systemName: context.state.isRecording ? "pause.fill" : "play.fill")
                                .font(.title3)
                        }
                        .tint(context.state.isRecording ? .orange : .green)

                        Button(intent: StopRecordingLiveActivityIntent()) {
                            Image(systemName: "stop.fill")
                                .font(.title3)
                        }
                        .tint(.red)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.isRecording ? "Recording" : "Paused")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: "mic.fill")
                    .foregroundStyle(context.state.isRecording ? .red : .orange)
            } compactTrailing: {
                Text(formatDuration(context.state.duration))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .font(.caption)
            } minimal: {
                Image(systemName: "mic.fill")
                    .foregroundStyle(context.state.isRecording ? .red : .orange)
            }
        }
    }

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<RecordingActivityAttributes>) -> some View {
        HStack(spacing: 16) {
            // Mic icon with state indicator
            ZStack {
                Circle()
                    .fill(context.state.isRecording ? Color.red.opacity(0.2) : Color.orange.opacity(0.2))
                    .frame(width: 44, height: 44)
                Image(systemName: "mic.fill")
                    .font(.title3)
                    .foregroundStyle(context.state.isRecording ? .red : .orange)
            }

            // Duration + State
            VStack(alignment: .leading, spacing: 2) {
                Text(formatDuration(context.state.duration))
                    .font(.title3.monospacedDigit())
                    .contentTransition(.numericText())
                Text(context.state.isRecording ? "Recording" : "Paused")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Controls
            HStack(spacing: 12) {
                Button(intent: TogglePauseLiveActivityIntent()) {
                    Image(systemName: context.state.isRecording ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title)
                }
                .tint(context.state.isRecording ? .orange : .green)

                Button(intent: StopRecordingLiveActivityIntent()) {
                    Image(systemName: "stop.circle.fill")
                        .font(.title)
                }
                .tint(.red)
            }
        }
        .padding()
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
#endif
