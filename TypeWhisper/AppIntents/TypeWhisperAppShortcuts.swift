import AppIntents

struct TypeWhisperAppShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartRecordingIntent(),
            phrases: [
                "Start recording in \(.applicationName)",
                "Begin dictation with \(.applicationName)",
                "Start \(.applicationName) recording"
            ],
            shortTitle: "Start Recording",
            systemImageName: "mic.fill"
        )
        AppShortcut(
            intent: StopRecordingIntent(),
            phrases: [
                "Stop recording in \(.applicationName)",
                "Finish dictation in \(.applicationName)",
                "Stop \(.applicationName) recording"
            ],
            shortTitle: "Stop Recording",
            systemImageName: "stop.fill"
        )
        AppShortcut(
            intent: TranscribeFileIntent(),
            phrases: [
                "Transcribe file with \(.applicationName)",
                "Use \(.applicationName) for this audio file"
            ],
            shortTitle: "Transcribe File",
            systemImageName: "waveform"
        )
        AppShortcut(
            intent: GetLastTranscriptionIntent(),
            phrases: [
                "Get latest note from \(.applicationName)",
                "Show last transcription in \(.applicationName)"
            ],
            shortTitle: "Last Transcription",
            systemImageName: "doc.text"
        )
    }
}
