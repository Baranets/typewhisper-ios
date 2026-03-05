import AppIntents

enum TranslationTargetOption: String, AppEnum {
    case none
    case de
    case en
    case fr
    case es
    case it

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Translation Target")
    }

    static var caseDisplayRepresentations: [TranslationTargetOption: DisplayRepresentation] {
        [
            .none: "No Translation",
            .de: "Deutsch",
            .en: "English",
            .fr: "Français",
            .es: "Español",
            .it: "Italiano"
        ]
    }

    var codeOrNil: String? {
        self == .none ? nil : rawValue
    }
}
