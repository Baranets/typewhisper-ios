import Foundation

enum IntentError: LocalizedError {
    case modelNotLoaded
    case microphonePermissionMissing
    case alreadyRecording
    case notRecording
    case timeout
    case invalidParameter(String)
    case transcriptionFailed(String)
    case noHistory

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            "No model loaded. Please load a transcription model in TypeWhisper first."
        case .microphonePermissionMissing:
            "Microphone permission is missing. Please enable it in Settings."
        case .alreadyRecording:
            "Recording is already running."
        case .notRecording:
            "There is no active recording."
        case .timeout:
            "The operation timed out before transcription finished."
        case .invalidParameter(let message):
            "Invalid parameter: \(message)"
        case .transcriptionFailed(let message):
            "Transcription failed: \(message)"
        case .noHistory:
            "No previous transcription available."
        }
    }
}
