import AppIntents
import Foundation

struct ProfileEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Profile")
    static let defaultQuery = ProfileQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct ProfileQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [ProfileEntity] {
        try await TypeWhisperIntentFacade.shared.ensureInitialized()
        let all = TypeWhisperIntentFacade.shared.profileService.profiles
        return all
            .filter { identifiers.contains($0.id) }
            .map { ProfileEntity(id: $0.id, name: $0.name) }
    }

    @MainActor
    func suggestedEntities() async throws -> [ProfileEntity] {
        try await TypeWhisperIntentFacade.shared.ensureInitialized()
        return TypeWhisperIntentFacade.shared.profileService.profiles
            .filter(\.isEnabled)
            .map { ProfileEntity(id: $0.id, name: $0.name) }
    }

    @MainActor
    func defaultResult() async -> ProfileEntity? {
        try? await TypeWhisperIntentFacade.shared.ensureInitialized()
        let first = TypeWhisperIntentFacade.shared.profileService.profiles.first(where: \.isEnabled)
        return first.map { ProfileEntity(id: $0.id, name: $0.name) }
    }
}
