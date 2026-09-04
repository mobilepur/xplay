import Foundation

@MainActor
final class AppSettings {
    enum MenuBarContent: String, CaseIterable {
        case xplay
        case nameAndTarget
        case name
        case target
    }

    enum ClickAction: String, CaseIterable {
        case play
        case menu
    }

    private enum ClickBehavior: String {
        case playOnLeft
        case playOnRight
    }

    private let defaults: UserDefaults
    private let acceptsMacrosKey: String
    private let menuBarContentKey: String
    private let clickBehaviorKey: String
    private var clickBehavior: ClickBehavior

    private(set) var acceptsMacros: Bool
    private(set) var menuBarContent: MenuBarContent

    var leftClickAction: ClickAction {
        clickBehavior == .playOnLeft ? .play : .menu
    }

    var rightClickAction: ClickAction {
        clickBehavior == .playOnRight ? .play : .menu
    }

    init(defaults: UserDefaults = .standard, storageKey: String = "settings") {
        self.defaults = defaults
        acceptsMacrosKey = "\(storageKey).acceptsMacros"
        menuBarContentKey = "\(storageKey).menuBarContent"
        clickBehaviorKey = "\(storageKey).clickBehavior"
        acceptsMacros = defaults.bool(forKey: acceptsMacrosKey)
        menuBarContent = defaults.string(forKey: menuBarContentKey)
            .flatMap(MenuBarContent.init(rawValue:)) ?? .xplay
        clickBehavior = defaults.string(forKey: clickBehaviorKey)
            .flatMap(ClickBehavior.init(rawValue:)) ?? .playOnLeft
    }

    func setAcceptsMacros(_ acceptsMacros: Bool) {
        self.acceptsMacros = acceptsMacros
        defaults.set(acceptsMacros, forKey: acceptsMacrosKey)
    }

    func setMenuBarContent(_ content: MenuBarContent) {
        menuBarContent = content
        defaults.set(content.rawValue, forKey: menuBarContentKey)
    }

    func setLeftClickAction(_ action: ClickAction) {
        switch action {
        case .play:
            setClickBehavior(.playOnLeft)
        case .menu:
            setClickBehavior(.playOnRight)
        }
    }

    func setRightClickAction(_ action: ClickAction) {
        switch action {
        case .play:
            setClickBehavior(.playOnRight)
        case .menu:
            setClickBehavior(.playOnLeft)
        }
    }

    private func setClickBehavior(_ behavior: ClickBehavior) {
        clickBehavior = behavior
        defaults.set(behavior.rawValue, forKey: clickBehaviorKey)
    }
}
