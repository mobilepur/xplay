import Foundation

@MainActor
final class AppSettings {
    private let defaults: UserDefaults
    private let acceptsMacrosKey: String

    private(set) var acceptsMacros: Bool

    init(defaults: UserDefaults = .standard, storageKey: String = "settings") {
        self.defaults = defaults
        acceptsMacrosKey = "\(storageKey).acceptsMacros"
        acceptsMacros = defaults.bool(forKey: acceptsMacrosKey)
    }

    func setAcceptsMacros(_ acceptsMacros: Bool) {
        self.acceptsMacros = acceptsMacros
        defaults.set(acceptsMacros, forKey: acceptsMacrosKey)
    }
}
