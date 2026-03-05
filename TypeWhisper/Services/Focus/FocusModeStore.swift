import Foundation

actor FocusModeStore {
    private let defaults: UserDefaults?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults? = UserDefaults(suiteName: TypeWhisperConstants.appGroupIdentifier)) {
        self.defaults = defaults
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadRuntimeConfiguration() -> FocusRuntimeConfiguration {
        guard
            let defaults,
            let data = defaults.data(forKey: TypeWhisperConstants.SharedDefaults.focusRuntimeConfiguration),
            let config = try? decoder.decode(FocusRuntimeConfiguration.self, from: data)
        else {
            return .inactive
        }
        return config
    }

    func saveRuntimeConfiguration(_ config: FocusRuntimeConfiguration) {
        guard let defaults, let data = try? encoder.encode(config) else { return }
        defaults.set(data, forKey: TypeWhisperConstants.SharedDefaults.focusRuntimeConfiguration)
    }

    func loadMappings() -> [FocusProfileMapping] {
        guard
            let defaults,
            let data = defaults.data(forKey: TypeWhisperConstants.SharedDefaults.focusProfileMappings),
            let mappings = try? decoder.decode([FocusProfileMapping].self, from: data)
        else {
            return []
        }
        return mappings
    }

    func saveMappings(_ mappings: [FocusProfileMapping]) {
        guard let defaults, let data = try? encoder.encode(mappings) else { return }
        defaults.set(data, forKey: TypeWhisperConstants.SharedDefaults.focusProfileMappings)
    }
}
