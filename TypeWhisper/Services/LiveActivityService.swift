#if canImport(ActivityKit)
import ActivityKit
import Foundation

// Free functions to avoid @MainActor isolation issues with Activity APIs
private func updateActivityAsync(id: String, state: RecordingActivityAttributes.ContentState) {
    guard let activity = Activity<RecordingActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
    let content = ActivityContent(state: state, staleDate: nil)
    Task {
        await activity.update(content)
    }
}

private func endActivityAsync(id: String, state: RecordingActivityAttributes.ContentState) {
    guard let activity = Activity<RecordingActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
    let content = ActivityContent(state: state, staleDate: nil)
    Task {
        await activity.end(content, dismissalPolicy: .immediate)
    }
}

@MainActor
final class LiveActivityService {
    private var currentActivityID: String?
    private var updateTimer: Timer?

    var durationProvider: (() -> TimeInterval)?
    var audioLevelProvider: (() -> Float)?
    var isRecordingProvider: (() -> Bool)?

    func startActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let initialState = RecordingActivityAttributes.ContentState(
            isRecording: true,
            duration: 0,
            audioLevel: 0
        )

        do {
            let activity = try Activity.request(
                attributes: RecordingActivityAttributes(),
                content: .init(state: initialState, staleDate: nil),
                pushType: nil
            )
            currentActivityID = activity.id
        } catch {
            // Live Activity not available
        }

        startPeriodicUpdates()
    }

    func updateActivity(isRecording: Bool) {
        guard let activityID = currentActivityID else { return }

        let state = RecordingActivityAttributes.ContentState(
            isRecording: isRecording,
            duration: durationProvider?() ?? 0,
            audioLevel: audioLevelProvider?() ?? 0
        )

        updateActivityAsync(id: activityID, state: state)
    }

    func endActivity() {
        stopPeriodicUpdates()

        guard let activityID = currentActivityID else {
            return
        }

        let finalState = RecordingActivityAttributes.ContentState(
            isRecording: false,
            duration: durationProvider?() ?? 0,
            audioLevel: 0
        )

        endActivityAsync(id: activityID, state: finalState)
        currentActivityID = nil
    }

    func startPeriodicUpdates() {
        stopPeriodicUpdates()

        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let activityID = self.currentActivityID else { return }

                let state = RecordingActivityAttributes.ContentState(
                    isRecording: self.isRecordingProvider?() ?? true,
                    duration: self.durationProvider?() ?? 0,
                    audioLevel: self.audioLevelProvider?() ?? 0
                )

                updateActivityAsync(id: activityID, state: state)
            }
        }
    }

    func stopPeriodicUpdates() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
}
#endif
