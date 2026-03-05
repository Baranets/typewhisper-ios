import Foundation

struct IntentTranscriptionPayload: Codable, Sendable {
    enum Status: String, Codable, Sendable {
        case recordingStarted = "recording_started"
        case transcriptionDone = "transcription_done"
        case transcriptionDoneUntranslated = "transcription_done_untranslated"
    }

    enum Source: String, Codable, Sendable {
        case live
        case file
        case history
    }

    let status: Status
    let text: String
    let language: String?
    let duration: TimeInterval?
    let source: Source
    let timestamp: Date

    init(
        status: Status,
        text: String,
        language: String?,
        duration: TimeInterval?,
        source: Source,
        timestamp: Date = Date()
    ) {
        self.status = status
        self.text = text
        self.language = language
        self.duration = duration
        self.source = source
        self.timestamp = timestamp
    }

    var jsonString: String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self),
              let json = String(data: data, encoding: .utf8) else {
            return "{\"status\":\"serialization_error\"}"
        }
        return json
    }
}
