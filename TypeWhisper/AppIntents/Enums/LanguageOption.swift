import AppIntents

enum LanguageOption: String, AppEnum {
    case auto
    case de
    case en
    case fr
    case es
    case it

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Input Language")
    }

    static var caseDisplayRepresentations: [LanguageOption: DisplayRepresentation] {
        [
            .auto: "Auto",
            .de: "Deutsch",
            .en: "English",
            .fr: "Français",
            .es: "Español",
            .it: "Italiano"
        ]
    }

    var codeOrNil: String? {
        self == .auto ? nil : rawValue
    }
}
