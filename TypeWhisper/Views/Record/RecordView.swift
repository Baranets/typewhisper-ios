import SwiftUI

struct RecordView: View {
    @EnvironmentObject private var viewModel: RecordingViewModel
    @EnvironmentObject private var modelManager: ModelManagerViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var showModelManager = false
    @State private var keyboardActivated = false
    @State private var keyboardHasFullAccess = false

    private var isActiveRecording: Bool {
        viewModel.state == .recording || viewModel.state == .paused
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                // Status / Partial Text
                statusSection

                Spacer()

                // Microphone Button
                MicrophoneButton(
                    isRecording: isActiveRecording,
                    isPaused: viewModel.state == .paused,
                    audioLevel: viewModel.audioLevel
                ) {
                    viewModel.toggleRecording()
                }
                .padding(.bottom, 8)

                // Recording duration
                if isActiveRecording {
                    Text(formatDuration(viewModel.recordingDuration))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                // Recording controls
                if isActiveRecording {
                    recordingControls
                        .padding(.top, 16)
                }

                Spacer()

                // Result Card
                if case .done(let text) = viewModel.state {
                    ResultCardView(text: text) {
                        viewModel.dismissResult()
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
            .navigationTitle("TypeWhisper")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    modelStatusIndicator
                }
            }
            .navigationDestination(isPresented: $showModelManager) {
                ModelManagerView()
            }
            .overlay {
                if viewModel.state == .processing {
                    processingOverlay
                }
            }
            .alert("Microphone Access", isPresented: .constant(viewModel.needsMicPermission && viewModel.state == .idle)) {
                Button("Grant Access") {
                    viewModel.requestMicPermission()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("TypeWhisper needs microphone access to transcribe your speech.")
            }
            .onAppear { checkKeyboardSetup() }
            .onChange(of: scenePhase) {
                if scenePhase == .active {
                    checkKeyboardSetup()
                }
            }
        }
    }

    @ViewBuilder
    private var recordingControls: some View {
        HStack(spacing: 32) {
            // Cancel
            Button {
                viewModel.cancelRecording()
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .sensoryFeedback(.impact(weight: .light), trigger: viewModel.state)

            // Pause / Resume
            Button {
                if viewModel.state == .paused {
                    viewModel.resumeRecording()
                } else {
                    viewModel.pauseRecording()
                }
            } label: {
                Image(systemName: viewModel.state == .paused ? "play.circle.fill" : "pause.circle.fill")
                    .font(.title)
                    .foregroundStyle(viewModel.state == .paused ? .green : .orange)
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: viewModel.state)

            // Restart
            Button {
                viewModel.restartRecording()
            } label: {
                Image(systemName: "arrow.counterclockwise.circle")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .sensoryFeedback(.impact(weight: .light), trigger: viewModel.state)
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if viewModel.state == .processing {
            EmptyView()
        } else if viewModel.state == .paused, !viewModel.partialText.isEmpty {
            VStack(spacing: 8) {
                Text("Paused")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .textCase(.uppercase)
                ScrollView {
                    Text(viewModel.partialText)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxHeight: 200)
            }
        } else if viewModel.state == .paused {
            Text("Paused")
                .font(.headline)
                .foregroundStyle(.orange)
        } else if viewModel.state == .recording, !viewModel.partialText.isEmpty {
            ScrollView {
                Text(viewModel.partialText)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .frame(maxHeight: 200)
        } else if viewModel.state == .recording {
            WaveformView(audioLevel: viewModel.audioLevel)
                .frame(height: 60)
                .padding(.horizontal, 40)
        } else if modelManager.isLoadingModel {
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text("Loading model...")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .padding()
        } else if !modelManager.isModelReady {
            VStack(spacing: 8) {
                Image(systemName: "arrow.down.circle")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("No model loaded")
                    .font(.headline)
                Text("Go to Settings → Models to download a speech recognition model.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        } else if case .error(let message) = viewModel.state {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.red)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        } else if viewModel.state == .idle, modelManager.isModelReady, !keyboardActivated {
            VStack(spacing: 8) {
                Image(systemName: "keyboard.badge.ellipsis")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("Enable Keyboard")
                    .font(.headline)
                Text("Settings > General > Keyboard > Keyboards > Add New Keyboard > TypeWhisper")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
                .padding(.top, 4)
            }
            .padding()
        } else if viewModel.state == .idle, modelManager.isModelReady, !keyboardHasFullAccess {
            VStack(spacing: 8) {
                Image(systemName: "keyboard.badge.ellipsis")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("Allow Full Access")
                    .font(.headline)
                Text("Settings > General > Keyboard > Keyboards > TypeWhisper > Allow Full Access")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
                .padding(.top, 4)
            }
            .padding()
        }
    }

    @ViewBuilder
    private var modelStatusIndicator: some View {
        if let name = modelManager.activeModelName {
            Button {
                showModelManager = true
            } label: {
                Text(name)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.fill.tertiary, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var processingOverlay: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text(viewModel.processingLabel)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .offset(y: -80)
        .background(.black.opacity(0.6))
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let tenths = Int((duration * 10).truncatingRemainder(dividingBy: 10))
        return String(format: "%d:%02d.%d", minutes, seconds, tenths)
    }

    private func checkKeyboardSetup() {
        if let keyboards = UserDefaults.standard.object(forKey: "AppleKeyboards") as? [String],
           keyboards.contains(TypeWhisperConstants.keyboardBundleId) {
            keyboardActivated = true
        } else {
            keyboardActivated = false
        }
        guard let defaults = UserDefaults(suiteName: TypeWhisperConstants.appGroupIdentifier) else { return }
        defaults.synchronize()
        keyboardHasFullAccess = defaults.bool(forKey: TypeWhisperConstants.SharedDefaults.keyboardHasFullAccess)
    }
}
