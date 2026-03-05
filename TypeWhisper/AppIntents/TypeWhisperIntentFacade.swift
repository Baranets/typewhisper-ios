import AppIntents
import Foundation
import UIKit

@MainActor
final class TypeWhisperIntentFacade {
    static let shared = TypeWhisperIntentFacade()

    private let container = ServiceContainer.shared
    private var didInitialize = false

    var profileService: ProfileService { container.profileService }

    private init() {}

    func ensureInitialized() async throws {
        guard !didInitialize else { return }
        await container.initialize()
        didInitialize = true
    }

    func startRecording(
        language: LanguageOption,
        profile: ProfileEntity?,
        translationTarget: TranslationTargetOption
    ) async throws -> IntentTranscriptionPayload {
        try await ensureInitialized()

        guard container.modelManagerService.activeEngine?.isModelLoaded == true else {
            throw IntentError.modelNotLoaded
        }

        guard container.audioRecordingService.hasMicrophonePermission else {
            throw IntentError.microphonePermissionMissing
        }

        if container.recordingViewModel.state == .recording {
            throw IntentError.alreadyRecording
        }

        if let profile {
            container.recordingViewModel.selectedProfile = profileService.profiles.first(where: { $0.id == profile.id })
            if container.recordingViewModel.selectedProfile == nil {
                throw IntentError.invalidParameter("Unknown profile")
            }
        } else {
            container.recordingViewModel.selectedProfile = nil
        }

        container.settingsViewModel.selectedLanguage = language.codeOrNil

        if let target = translationTarget.codeOrNil {
            container.settingsViewModel.translationEnabled = true
            container.settingsViewModel.translationTargetLanguage = target
        } else {
            container.settingsViewModel.translationEnabled = false
        }
        container.recordingViewModel.applyIntentOverrides(
            language: language.codeOrNil,
            translationTarget: translationTarget.codeOrNil
        )

        container.recordingViewModel.startRecording()

        guard container.recordingViewModel.state == .recording else {
            container.recordingViewModel.resetIntentOverrides()
            throw IntentError.transcriptionFailed("Could not start recording")
        }

        return IntentTranscriptionPayload(
            status: .recordingStarted,
            text: "Recording started",
            language: container.settingsViewModel.selectedLanguage,
            duration: nil,
            source: .live
        )
    }

    func stopRecording(timeout: Duration = .seconds(20)) async throws -> IntentTranscriptionPayload {
        try await ensureInitialized()

        guard container.recordingViewModel.state == .recording else {
            throw IntentError.notRecording
        }

        container.recordingViewModel.stopRecording()
        let finalState = await container.recordingViewModel.waitForFinalState(timeout: timeout)

        switch finalState {
        case .done(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw IntentError.transcriptionFailed("No text returned")
            }
            return IntentTranscriptionPayload(
                status: .transcriptionDone,
                text: trimmed,
                language: container.settingsViewModel.selectedLanguage,
                duration: container.recordingViewModel.lastTranscriptionDuration,
                source: .live
            )
        case .error(let message):
            throw IntentError.transcriptionFailed(message)
        case .idle:
            throw IntentError.transcriptionFailed("No audio captured")
        default:
            throw IntentError.timeout
        }
    }

    func transcribeFile(
        file: IntentFile,
        language: LanguageOption,
        translationTarget: TranslationTargetOption,
        saveToHistory: Bool,
        copyToClipboard: Bool
    ) async throws -> IntentTranscriptionPayload {
        try await ensureInitialized()

        guard container.modelManagerService.activeEngine?.isModelLoaded == true else {
            throw IntentError.modelNotLoaded
        }

        guard let fileURL = file.fileURL else {
            throw IntentError.invalidParameter("Input file URL is unavailable")
        }

        let ext = fileURL.pathExtension.lowercased()
        guard AudioFileService.supportedExtensions.contains(ext) else {
            throw IntentError.invalidParameter("Unsupported file type .\(ext)")
        }

        let samples = try await container.audioFileService.loadAudioSamples(from: fileURL)
        let result = try await container.modelManagerService.transcribe(
            audioSamples: samples,
            language: language.codeOrNil,
            task: .transcribe
        )

        let rawText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawText.isEmpty else {
            throw IntentError.transcriptionFailed("No text returned")
        }

        var finalText = container.snippetService.applySnippets(to: rawText)
        finalText = container.dictionaryService.applyCorrections(to: finalText)

        var translated = true
        if let targetCode = translationTarget.codeOrNil {
            do {
                let target = Locale.Language(identifier: targetCode)
                let source = result.detectedLanguage.map { Locale.Language(identifier: $0) }
                finalText = try await container.translationService.translate(text: finalText, from: source, to: target)
            } catch {
                translated = false
            }
        }

        if copyToClipboard {
            UIPasteboard.general.string = finalText
        }

        if saveToHistory {
            container.historyService.addRecord(
                rawText: rawText,
                finalText: finalText,
                durationSeconds: result.duration,
                language: result.detectedLanguage ?? language.codeOrNil,
                engineUsed: result.engineUsed.rawValue
            )
        }

        return IntentTranscriptionPayload(
            status: translated ? .transcriptionDone : .transcriptionDoneUntranslated,
            text: finalText,
            language: result.detectedLanguage ?? language.codeOrNil,
            duration: result.duration,
            source: .file
        )
    }

    func getLastTranscription() async throws -> IntentTranscriptionPayload {
        try await ensureInitialized()

        guard let record = container.historyService.lastRecord else {
            throw IntentError.noHistory
        }

        return IntentTranscriptionPayload(
            status: .transcriptionDone,
            text: record.finalText,
            language: record.language,
            duration: record.durationSeconds,
            source: .history,
            timestamp: record.timestamp
        )
    }
}
