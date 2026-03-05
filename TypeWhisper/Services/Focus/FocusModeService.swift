import Foundation
import Combine

@MainActor
final class FocusModeService: ObservableObject {
    @Published private(set) var runtimeConfiguration: FocusRuntimeConfiguration = .inactive
    @Published private(set) var mappings: [FocusProfileMapping] = []

    private let store: FocusModeStore
    private let profileService: ProfileService

    init(store: FocusModeStore = FocusModeStore(), profileService: ProfileService) {
        self.store = store
        self.profileService = profileService
    }

    func load() async {
        runtimeConfiguration = await store.loadRuntimeConfiguration()
        mappings = await store.loadMappings()
    }

    func setMapping(focus: FocusModeIdentifier, profileID: UUID?) async {
        if let profileID {
            mappings.removeAll { $0.focusIdentifier == focus }
            mappings.append(FocusProfileMapping(focusIdentifier: focus, profileID: profileID))
        } else {
            mappings.removeAll { $0.focusIdentifier == focus }
        }
        await store.saveMappings(mappings)
    }

    func mappedProfile(for focus: FocusModeIdentifier) -> Profile? {
        guard let mapping = mappings.first(where: { $0.focusIdentifier == focus }) else { return nil }
        return profileService.profiles.first(where: { $0.id == mapping.profileID })
    }

    func activateFocus(_ focus: FocusModeIdentifier) async throws {
        guard let profile = mappedProfile(for: focus) else {
            throw FocusModeError.profileNotFound
        }

        let config = FocusRuntimeConfiguration(
            isFocusActive: true,
            focusIdentifier: focus,
            selectedProfileID: profile.id,
            whisperModeOverride: profile.whisperModeOverride,
            translationTargetLanguageOverride: profile.translationTargetLanguage,
            notificationBatchMode: .untilFocusEnds,
            updatedAt: Date()
        )

        runtimeConfiguration = config
        await store.saveRuntimeConfiguration(config)
    }

    func deactivateFocus() async {
        runtimeConfiguration = .inactive
        await store.saveRuntimeConfiguration(.inactive)
    }
}
