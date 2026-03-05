import AppIntents

struct StopRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Recording"
    static let description = IntentDescription("Stop the current TypeWhisper recording and return the transcription.")
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let payload = try await TypeWhisperIntentFacade.shared.stopRecording()
        return .result(
            value: payload.jsonString,
            dialog: IntentDialog("Transcription ready.")
        )
    }
}
