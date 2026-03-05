import AppIntents

struct StartRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Recording"
    static let description = IntentDescription("Start a new TypeWhisper recording session.")
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Language", default: .auto)
    var language: LanguageOption

    @Parameter(title: "Profile")
    var profile: ProfileEntity?

    @Parameter(title: "Translation", default: .none)
    var translationTarget: TranslationTargetOption

    init() {
        self.language = .auto
        self.profile = nil
        self.translationTarget = .none
    }

    init(language: LanguageOption, profile: ProfileEntity? = nil, translationTarget: TranslationTargetOption = .none) {
        self.language = language
        self.profile = profile
        self.translationTarget = translationTarget
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let payload = try await TypeWhisperIntentFacade.shared.startRecording(
            language: language,
            profile: profile,
            translationTarget: translationTarget
        )

        return .result(
            value: payload.jsonString,
            dialog: IntentDialog("Recording started in TypeWhisper.")
        )
    }
}
