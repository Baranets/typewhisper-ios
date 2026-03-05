import AVFoundation
import Combine
import Foundation

enum RecordingDeviceEvent: Equatable, Sendable {
    case switchedToBluetooth(String)
    case switchedToWired(String)
    case switchedToBuiltIn
    case bluetoothDisconnectedFallback
}

final class AudioRouteCoordinator: ObservableObject, @unchecked Sendable {
    enum RouteKind: String, Sendable {
        case bluetooth
        case wired
        case builtIn
        case other
    }

    struct RouteInfo: Equatable, Sendable {
        let kind: RouteKind
        let name: String
        let portTypeRawValue: String
    }

    private let center: NotificationCenter
    private var cancellables = Set<AnyCancellable>()

    @Published private(set) var currentRoute: RouteInfo = RouteInfo(kind: .builtIn, name: "Built-in", portTypeRawValue: AVAudioSession.Port.builtInMic.rawValue)

    let eventPublisher = PassthroughSubject<RecordingDeviceEvent, Never>()

    init(center: NotificationCenter = .default) {
        self.center = center
    }

    func beginObserving() {
        center.publisher(for: AVAudioSession.routeChangeNotification)
            .sink { [weak self] note in
                guard let self else { return }
                self.handleRouteChange(note)
            }
            .store(in: &cancellables)

        center.publisher(for: AVAudioSession.interruptionNotification)
            .sink { [weak self] note in
                self?.handleInterruption(note)
            }
            .store(in: &cancellables)

        center.publisher(for: AVAudioSession.mediaServicesWereResetNotification)
            .sink { [weak self] _ in
                self?.refreshCurrentRoute()
            }
            .store(in: &cancellables)

        refreshCurrentRoute()
    }

    func stopObserving() {
        cancellables.removeAll()
    }

    func configureSession(bluetoothRoutingEnabled: Bool, preferVoiceIsolation: Bool) throws {
        let session = AVAudioSession.sharedInstance()
        var options: AVAudioSession.CategoryOptions = [.defaultToSpeaker, .duckOthers]
        if bluetoothRoutingEnabled {
            options.insert(.allowBluetooth)
            options.insert(.allowBluetoothA2DP)
        }

        do {
            let mode: AVAudioSession.Mode = preferVoiceIsolation ? .voiceChat : .default
            try session.setCategory(.playAndRecord, mode: mode, options: options)
        } catch {
            try session.setCategory(.playAndRecord, mode: .default, options: options)
        }
        try session.setActive(true)

        if bluetoothRoutingEnabled {
            try applyPreferredInput()
        }
        refreshCurrentRoute()
    }

    func applyPreferredInput() throws {
        let session = AVAudioSession.sharedInstance()
        let availableInputs = session.availableInputs ?? []

        let bluetoothPort = availableInputs.first {
            $0.portType == .bluetoothHFP || $0.portType == .bluetoothLE || $0.portType == .bluetoothA2DP
        }

        if let bluetoothPort {
            try session.setPreferredInput(bluetoothPort)
        } else {
            try session.setPreferredInput(nil)
        }

        refreshCurrentRoute()
    }

    func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func handleRouteChange(_ notification: Notification) {
        let previous = currentRoute
        refreshCurrentRoute()

        if previous.kind == .bluetooth, currentRoute.kind != .bluetooth {
            eventPublisher.send(.bluetoothDisconnectedFallback)
            return
        }

        switch currentRoute.kind {
        case .bluetooth:
            eventPublisher.send(.switchedToBluetooth(currentRoute.name))
        case .wired:
            eventPublisher.send(.switchedToWired(currentRoute.name))
        case .builtIn:
            eventPublisher.send(.switchedToBuiltIn)
        case .other:
            break
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard
            let userInfo = notification.userInfo,
            let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
            let interruptionType = AVAudioSession.InterruptionType(rawValue: typeValue)
        else {
            return
        }

        if interruptionType == .ended {
            try? AVAudioSession.sharedInstance().setActive(true)
            try? applyPreferredInput()
        }
    }

    private func refreshCurrentRoute() {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        guard let output = outputs.first else {
            currentRoute = RouteInfo(kind: .other, name: "Unknown", portTypeRawValue: "unknown")
            return
        }

        let kind: RouteKind
        switch output.portType {
        case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
            kind = .bluetooth
        case .headphones, .headsetMic, .lineOut, .usbAudio, .carAudio:
            kind = .wired
        case .builtInMic, .builtInReceiver, .builtInSpeaker:
            kind = .builtIn
        default:
            kind = .other
        }

        currentRoute = RouteInfo(kind: kind, name: output.portName, portTypeRawValue: output.portType.rawValue)
    }
}
