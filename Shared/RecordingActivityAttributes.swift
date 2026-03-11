#if canImport(ActivityKit)
import ActivityKit
import Foundation

struct RecordingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var isRecording: Bool
        var duration: TimeInterval
        var audioLevel: Float
    }
}
#endif
