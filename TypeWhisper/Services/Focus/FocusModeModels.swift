import Foundation

enum FocusModeKind: String, Codable, CaseIterable, Sendable {
    case work
    case personal
    case sleep
    case driving
    case fitness
    case mindfulness
    case gaming
    case reading
    case custom
}

struct FocusModeIdentifier: Codable, Sendable, Equatable, Hashable {
    let kind: FocusModeKind
    let systemIdentifier: String?

    static var `default`: FocusModeIdentifier {
        FocusModeIdentifier(kind: .work, systemIdentifier: nil)
    }

    var displayName: String {
        if let systemIdentifier, !systemIdentifier.isEmpty {
            return systemIdentifier
        }
        return kind.rawValue.capitalized
    }
}

struct FocusProfileMapping: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let focusIdentifier: FocusModeIdentifier
    let profileID: UUID
    let updatedAt: Date

    init(
        id: UUID = UUID(),
        focusIdentifier: FocusModeIdentifier,
        profileID: UUID,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.focusIdentifier = focusIdentifier
        self.profileID = profileID
        self.updatedAt = updatedAt
    }
}

enum FocusNotificationBatchMode: String, Codable, CaseIterable, Sendable {
    case off
    case whileFocused
    case untilFocusEnds
}

struct FocusRuntimeConfiguration: Codable, Sendable, Equatable {
    var isFocusActive: Bool
    var focusIdentifier: FocusModeIdentifier?
    var selectedProfileID: UUID?
    var whisperModeOverride: Bool?
    var translationTargetLanguageOverride: String?
    var notificationBatchMode: FocusNotificationBatchMode
    var updatedAt: Date

    static let inactive = FocusRuntimeConfiguration(
        isFocusActive: false,
        focusIdentifier: nil,
        selectedProfileID: nil,
        whisperModeOverride: nil,
        translationTargetLanguageOverride: nil,
        notificationBatchMode: .off,
        updatedAt: Date()
    )
}

enum FocusModeError: LocalizedError {
    case storeUnavailable
    case profileNotFound

    var errorDescription: String? {
        switch self {
        case .storeUnavailable:
            return "Focus store unavailable"
        case .profileNotFound:
            return "Selected profile for focus mode was not found"
        }
    }
}
