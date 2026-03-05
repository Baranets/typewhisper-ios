import AppIntents

struct TranscribeFileIntent: AppIntent {
    static let title: LocalizedStringResource = "Transcribe Audio File"
    static let description = IntentDescription("Transcribe a local audio file with TypeWhisper.")
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Audio File")
    var audioFile: IntentFile

    @Parameter(title: "Language", default: .auto)
    var language: LanguageOption

    @Parameter(title: "Translation", default: .none)
    var translationTarget: TranslationTargetOption

    @Parameter(title: "Save to History", default: true)
    var saveToHistory: Bool

    @Parameter(title: "Copy to Clipboard", default: false)
    var copyToClipboard: Bool

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let payload = try await TypeWhisperIntentFacade.shared.transcribeFile(
            file: audioFile,
            language: language,
            translationTarget: translationTarget,
            saveToHistory: saveToHistory,
            copyToClipboard: copyToClipboard
        )

        let dialog = payload.status == .transcriptionDoneUntranslated
            ? "Transcription completed, translation fallback used."
            : "File transcription completed."

        return .result(
            value: payload.jsonString,
            dialog: IntentDialog("\(dialog)")
        )
    }
}
