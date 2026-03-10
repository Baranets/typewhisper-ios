import Foundation
@preconcurrency import AVFoundation
import Speech
import UIKit
import os.log

/// Calculate audio levels from buffer — free function to avoid @MainActor metatype isolation
private func calculateFlowAudioLevels(from buffer: AVAudioPCMBuffer, barCount: Int) -> [Float] {
    guard let channelData = buffer.floatChannelData else {
        return Array(repeating: 0, count: barCount)
    }

    let frameLength = Int(buffer.frameLength)
    guard frameLength > 0 else {
        return Array(repeating: 0, count: barCount)
    }

    let samplesPerBar = frameLength / barCount
    var levels = [Float]()

    for barIndex in 0..<barCount {
        let startSample = barIndex * samplesPerBar
        let endSample = min(startSample + samplesPerBar, frameLength)

        var sum: Float = 0
        for i in startSample..<endSample {
            let sample = channelData[0][i]
            sum += abs(sample)
        }

        let avgLevel = sum / Float(endSample - startSample)
        let normalizedLevel = min(avgLevel * 50.0, 1.0)
        levels.append(normalizedLevel)
    }

    return levels
}

/// Thread-safe holder for the active recognition request — allows audio tap to append buffers
private final class FlowRecognitionState: @unchecked Sendable {
    private let lock = NSLock()
    private var _request: SFSpeechAudioBufferRecognitionRequest?
    private var _bufferCount: Int = 0

    var request: SFSpeechAudioBufferRecognitionRequest? {
        lock.lock()
        defer { lock.unlock() }
        return _request
    }

    var bufferCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _bufferCount
    }

    func set(_ request: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock()
        _request = request
        if request != nil { _bufferCount = 0 }
        lock.unlock()
    }

    func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        _request?.append(buffer)
        _bufferCount += 1
        lock.unlock()
    }
}

/// Install audio tap from a nonisolated context — closures defined inside @MainActor methods
/// inherit actor isolation in Swift 6 and crash on the audio thread.
private func installFlowAudioTap(
    on inputNode: AVAudioNode,
    format: AVAudioFormat,
    recordingFlag: OSAllocatedUnfairLock<Bool>,
    defaults: UserDefaults?,
    recognitionState: FlowRecognitionState
) {
    inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
        // Always write audio levels for keyboard visualization
        let levels = calculateFlowAudioLevels(from: buffer, barCount: 24)
        let levelsAsDouble = levels.map { Double($0) }
        defaults?.set(levelsAsDouble, forKey: TypeWhisperConstants.SharedDefaults.audioLevels)
        defaults?.synchronize()

        // If recording, append buffer directly to the recognition request
        let currentlyRecording = recordingFlag.withLock { $0 }
        guard currentlyRecording else { return }

        recognitionState.appendBuffer(buffer)
    }
}

/// Manages "Flow Sessions" — the main app continuously records audio in the background
/// and the keyboard extension signals when to transcribe via shared UserDefaults.
/// Uses Apple's on-device speech recognition (SFSpeechRecognizer) directly.
@MainActor
class FlowSessionManager: ObservableObject {
    private let logger = Logger(subsystem: "com.typewhisper", category: "FlowSession")

    private let sharedDefaults = UserDefaults(suiteName: TypeWhisperConstants.appGroupIdentifier)

    @Published var isFlowSessionActive = false
    @Published var sessionExpiresAt: Date?
    @Published var isRecording = false
    @Published var lastTranscription: String?
    @Published var openedFromKeyboard = false
    private var audioEngine: AVAudioEngine?
    private var sessionTimer: Timer?
    private var pollingTimer: Timer?
    private var heartbeatTimer: Timer?

    private let isRecordingAtomic = OSAllocatedUnfairLock(initialState: false)
    private let recognitionState = FlowRecognitionState()
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionTimeoutWork: DispatchWorkItem?
    private var recognitionGeneration = 0
    private var appendedBufferCount = 0

    init() {
        checkExistingSession()
    }

    private func checkExistingSession() {
        guard let expires = sharedDefaults?.object(forKey: TypeWhisperConstants.SharedDefaults.flowSessionExpires) as? Date else {
            isFlowSessionActive = false
            return
        }

        if expires > Date() {
            isFlowSessionActive = true
            sessionExpiresAt = expires
            startFlowSession(duration: expires.timeIntervalSinceNow)
        } else {
            endFlowSession()
        }
    }

    // MARK: - Session Lifecycle

    func startFlowSession(duration: TimeInterval = 300) {
        logger.info("Starting Flow Session for \(Int(duration))s")

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            logger.error("Failed to configure audio session: \(error)")
            return
        }

        // Ensure speech recognition is authorized
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        if authStatus == .notDetermined {
            SFSpeechRecognizer.requestAuthorization { _ in }
        }

        sharedDefaults?.set("idle", forKey: TypeWhisperConstants.SharedDefaults.keyboardRecordingState)
        sharedDefaults?.removeObject(forKey: TypeWhisperConstants.SharedDefaults.transcriptionResult)
        sharedDefaults?.removeObject(forKey: TypeWhisperConstants.SharedDefaults.transcriptionError)
        sharedDefaults?.synchronize()

        startContinuousRecording()
        startPollingForKeyboardSignals()
        startHeartbeat()

        let expiresAt = Date().addingTimeInterval(duration)
        sessionExpiresAt = expiresAt
        isFlowSessionActive = true

        sharedDefaults?.set(true, forKey: TypeWhisperConstants.SharedDefaults.flowSessionActive)
        sharedDefaults?.set(expiresAt, forKey: TypeWhisperConstants.SharedDefaults.flowSessionExpires)
        sharedDefaults?.synchronize()

        sessionTimer?.invalidate()
        sessionTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.endFlowSession() }
        }

        logger.info("Flow Session started, expires at \(expiresAt)")

        NotificationCenter.default.post(name: .flowSessionStartedFromKeyboard, object: nil)
    }

    func endFlowSession() {
        logger.info("Ending Flow Session")

        sessionTimer?.invalidate()
        sessionTimer = nil
        pollingTimer?.invalidate()
        pollingTimer = nil
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        sharedDefaults?.removeObject(forKey: TypeWhisperConstants.SharedDefaults.flowHeartbeat)

        // Cancel any active recognition
        cancelRecognition()

        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        isFlowSessionActive = false
        isRecording = false
        isRecordingAtomic.withLock { $0 = false }
        sessionExpiresAt = nil

        sharedDefaults?.set(false, forKey: TypeWhisperConstants.SharedDefaults.flowSessionActive)
        sharedDefaults?.removeObject(forKey: TypeWhisperConstants.SharedDefaults.flowSessionExpires)
        sharedDefaults?.set("idle", forKey: TypeWhisperConstants.SharedDefaults.keyboardRecordingState)
        sharedDefaults?.synchronize()
    }

    func extendFlowSession(by duration: TimeInterval = 300) {
        guard isFlowSessionActive else {
            startFlowSession(duration: duration)
            return
        }

        let newExpiration = Date().addingTimeInterval(duration)
        sessionExpiresAt = newExpiration
        sharedDefaults?.set(newExpiration, forKey: TypeWhisperConstants.SharedDefaults.flowSessionExpires)
        sharedDefaults?.synchronize()

        sessionTimer?.invalidate()
        sessionTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.endFlowSession() }
        }
    }

    // MARK: - Audio Recording

    private func startContinuousRecording() {
        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else { return }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        installFlowAudioTap(
            on: inputNode,
            format: format,
            recordingFlag: isRecordingAtomic,
            defaults: sharedDefaults,
            recognitionState: recognitionState
        )

        do {
            engine.prepare()
            try engine.start()
        } catch {
            logger.error("Failed to start audio engine: \(error)")
        }
    }

    // MARK: - Speech Recognition

    private func startRecognition() {
        cancelRecognition()

        // Small delay to let SFSpeechRecognizer fully release previous session
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.startRecognitionNow()
        }
    }

    private func startRecognitionNow() {
        recognitionGeneration += 1
        let currentGeneration = recognitionGeneration
        logger.info("[REC] startRecognition gen=\(currentGeneration)")

        let language = sharedDefaults?.string(forKey: TypeWhisperConstants.SharedDefaults.transcriptionLanguage)
        let effectiveLanguage = (language == "auto") ? nil : language

        let recognizer: SFSpeechRecognizer
        if let lang = effectiveLanguage {
            recognizer = SFSpeechRecognizer(locale: Locale(identifier: lang)) ?? SFSpeechRecognizer()!
        } else {
            recognizer = SFSpeechRecognizer()!
        }

        guard recognizer.isAvailable else {
            logger.error("Speech recognizer not available")
            sharedDefaults?.set("Speech recognizer not available", forKey: TypeWhisperConstants.SharedDefaults.transcriptionError)
            sharedDefaults?.set("idle", forKey: TypeWhisperConstants.SharedDefaults.keyboardRecordingState)
            sharedDefaults?.synchronize()
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.addsPunctuation = true

        recognitionState.set(request)

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }

                // Ignore callbacks from stale recognition sessions
                guard self.recognitionGeneration == currentGeneration else {
                    self.logger.warning("[REC] STALE callback gen=\(currentGeneration) current=\(self.recognitionGeneration)")
                    return
                }

                self.logger.info("[REC] callback gen=\(currentGeneration) result=\(result != nil) final=\(result?.isFinal ?? false) err=\(error?.localizedDescription ?? "none")")

                // Check result FIRST - SFSpeechRecognizer can deliver both result and error
                if let result, result.isFinal {
                    let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.logger.info("[REC] FINAL: \(text.prefix(80))")

                    // Immediately block any further callbacks from this session
                    self.recognitionGeneration += 1
                    self.recognitionTimeoutWork?.cancel()
                    self.recognitionTimeoutWork = nil
                    self.recognitionTask?.cancel()
                    self.recognitionTask = nil
                    self.recognitionState.set(nil)

                    if text.isEmpty {
                        self.sharedDefaults?.set("No text recognized", forKey: TypeWhisperConstants.SharedDefaults.transcriptionError)
                    } else {
                        self.lastTranscription = text
                        self.sharedDefaults?.set(text, forKey: TypeWhisperConstants.SharedDefaults.transcriptionResult)
                        self.sharedDefaults?.removeObject(forKey: TypeWhisperConstants.SharedDefaults.transcriptionError)
                    }
                    self.sharedDefaults?.set("idle", forKey: TypeWhisperConstants.SharedDefaults.keyboardRecordingState)
                    self.sharedDefaults?.synchronize()
                } else if let error {
                    // Ignore cancellation errors from our own cleanup
                    let nsError = error as NSError
                    if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 216 {
                        self.logger.info("[REC] Ignoring cancellation error (216)")
                        return
                    }

                    self.logger.error("[REC] ERROR: \(error.localizedDescription) (isRecording=\(self.isRecording))")
                    self.recognitionTimeoutWork?.cancel()
                    self.recognitionTimeoutWork = nil
                    self.recognitionTask = nil
                    self.recognitionState.set(nil)

                    // Write error so keyboard can pick it up - but DON'T reset isRecording.
                    // If keyboard is still recording, it will stop and find this error.
                    // If already stopped, "stopped" handler will respond.
                    self.sharedDefaults?.set(error.localizedDescription, forKey: TypeWhisperConstants.SharedDefaults.transcriptionError)
                    self.sharedDefaults?.set("idle", forKey: TypeWhisperConstants.SharedDefaults.keyboardRecordingState)
                    self.sharedDefaults?.synchronize()
                }
            }
        }

        logger.info("[REC] Recognition started (lang: \(effectiveLanguage ?? "auto"))")
    }

    private func stopRecognition() {
        // End the audio stream — recognizer will produce final result via callback
        let hasRequest = recognitionState.request != nil
        let hasTask = recognitionTask != nil
        logger.info("[REC] stopRecognition: hasRequest=\(hasRequest), hasTask=\(hasTask)")
        recognitionState.request?.endAudio()

        // Timeout after 30s if no result
        let timeout = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.recognitionTask != nil else { return }
                self.logger.warning("[REC] TIMEOUT - recognition timed out after 30s")
                self.recognitionTask?.cancel()
                self.recognitionTask = nil
                self.recognitionState.set(nil)
                self.sharedDefaults?.set("Recognition timed out", forKey: TypeWhisperConstants.SharedDefaults.transcriptionError)
                self.sharedDefaults?.set("idle", forKey: TypeWhisperConstants.SharedDefaults.keyboardRecordingState)
                self.sharedDefaults?.synchronize()
            }
        }
        recognitionTimeoutWork = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: timeout)
    }

    private func cancelRecognition() {
        recognitionTimeoutWork?.cancel()
        recognitionTimeoutWork = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionState.set(nil)
    }

    // MARK: - Keyboard Signal Polling

    private func startPollingForKeyboardSignals() {
        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkKeyboardSignal() }
        }
    }

    private func checkKeyboardSignal() {
        guard let state = sharedDefaults?.string(forKey: TypeWhisperConstants.SharedDefaults.keyboardRecordingState) else { return }

        switch state {
        case "recording":
            if !isRecording {
                isRecording = true
                isRecordingAtomic.withLock { $0 = true }

                // Clean up stale data from previous recognition
                sharedDefaults?.removeObject(forKey: TypeWhisperConstants.SharedDefaults.transcriptionResult)
                sharedDefaults?.removeObject(forKey: TypeWhisperConstants.SharedDefaults.transcriptionError)
                sharedDefaults?.synchronize()

                logger.info("[FLOW] signal=recording, starting recognition (task=\(String(describing: self.recognitionTask)))")
                startRecognition()
            }

        case "stopped":
            let buffers = recognitionState.bufferCount
            logger.info("[FLOW] signal=stopped isRecording=\(self.isRecording) buffers=\(buffers) task=\(self.recognitionTask != nil)")

            isRecording = false
            isRecordingAtomic.withLock { $0 = false }

            sharedDefaults?.set("processing", forKey: TypeWhisperConstants.SharedDefaults.keyboardRecordingState)
            sharedDefaults?.synchronize()

            if recognitionTask != nil || recognitionState.request != nil {
                stopRecognition()
            } else {
                // No active recognition - respond immediately so keyboard doesn't hang
                logger.warning("[FLOW] stopped but no active recognition - responding with error")
                sharedDefaults?.set("Recognition not active", forKey: TypeWhisperConstants.SharedDefaults.transcriptionError)
                sharedDefaults?.set("idle", forKey: TypeWhisperConstants.SharedDefaults.keyboardRecordingState)
                sharedDefaults?.synchronize()
            }

        case "aborted":
            logger.info("[FLOW] signal=aborted isRecording=\(self.isRecording)")
            cancelRecognition()
            isRecording = false
            isRecordingAtomic.withLock { $0 = false }
            sharedDefaults?.set("idle", forKey: TypeWhisperConstants.SharedDefaults.keyboardRecordingState)
            sharedDefaults?.synchronize()

        default:
            break
        }
    }

    // MARK: - Heartbeat

    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        writeHeartbeat()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.writeHeartbeat()
        }
    }

    private func writeHeartbeat() {
        sharedDefaults?.set(Date(), forKey: TypeWhisperConstants.SharedDefaults.flowHeartbeat)
    }

    // MARK: - URL Handling

    @discardableResult
    func handleURL(_ url: URL) -> Bool {
        guard url.scheme == "typewhisper" else { return false }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)

        switch url.host {
        case "startflow":
            var duration: TimeInterval = 300
            if let durationParam = components?.queryItems?.first(where: { $0.name == "duration" })?.value,
               let durationValue = TimeInterval(durationParam) {
                duration = durationValue
            }
            openedFromKeyboard = true
            startFlowSession(duration: duration)
            return true

        case "endflow":
            endFlowSession()
            return true

        case "extendflow":
            var duration: TimeInterval = 300
            if let durationParam = components?.queryItems?.first(where: { $0.name == "duration" })?.value,
               let durationValue = TimeInterval(durationParam) {
                duration = durationValue
            }
            extendFlowSession(by: duration)
            return true

        default:
            return false
        }
    }
}

extension Notification.Name {
    static let flowSessionStartedFromKeyboard = Notification.Name("flowSessionStartedFromKeyboard")
}
