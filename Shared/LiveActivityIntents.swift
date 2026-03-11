#if canImport(ActivityKit)
import AppIntents
import Foundation

struct StopRecordingLiveActivityIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Recording"
    static let openAppWhenRun: Bool = true

    nonisolated(unsafe) static var handler: (@MainActor () -> Void)?

    @MainActor
    func perform() async throws -> some IntentResult {
        Self.handler?()
        return .result()
    }
}

struct TogglePauseLiveActivityIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Toggle Pause"
    static let openAppWhenRun: Bool = false

    nonisolated(unsafe) static var handler: (@MainActor () -> Void)?

    @MainActor
    func perform() async throws -> some IntentResult {
        Self.handler?()
        return .result()
    }
}
#endif
