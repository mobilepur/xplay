import Foundation
import XCTest
@testable import XPlay

final class AppSettingsTests: XCTestCase {
    @MainActor
    func testMenuBarSettingsDefaultToXPlayAndPlayOnLeft() {
        withDefaults { defaults in
            let settings = AppSettings(defaults: defaults)

            XCTAssertEqual(settings.menuBarContent, .xplay)
            XCTAssertEqual(settings.leftClickAction, .play)
            XCTAssertEqual(settings.rightClickAction, .menu)
        }
    }

    @MainActor
    func testEveryMenuBarContentModePersistsWithTheStoragePrefix() {
        withDefaults { defaults in
            for content in AppSettings.MenuBarContent.allCases {
                let settings = AppSettings(defaults: defaults, storageKey: "custom")

                settings.setMenuBarContent(content)

                XCTAssertEqual(settings.menuBarContent, content)
                XCTAssertEqual(defaults.string(forKey: "custom.menuBarContent"), content.rawValue)
                XCTAssertEqual(AppSettings(defaults: defaults, storageKey: "custom").menuBarContent, content)
                XCTAssertEqual(AppSettings(defaults: defaults).menuBarContent, .xplay)
            }
        }
    }

    @MainActor
    func testSwappingPlayToTheRightKeepsTheLeftMenuReachableAndPersists() {
        withDefaults { defaults in
            let settings = AppSettings(defaults: defaults, storageKey: "custom")

            settings.setRightClickAction(.play)

            XCTAssertEqual(settings.leftClickAction, .menu)
            XCTAssertEqual(settings.rightClickAction, .play)
            let reloaded = AppSettings(defaults: defaults, storageKey: "custom")
            XCTAssertEqual(reloaded.leftClickAction, .menu)
            XCTAssertEqual(reloaded.rightClickAction, .play)
            XCTAssertEqual(AppSettings(defaults: defaults).leftClickAction, .play)
            XCTAssertEqual(AppSettings(defaults: defaults).rightClickAction, .menu)
        }
    }

    @MainActor
    func testSwappingPlayBackToTheLeftKeepsTheRightMenuReachableAndPersists() {
        withDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            settings.setRightClickAction(.play)

            settings.setLeftClickAction(.play)

            XCTAssertEqual(settings.leftClickAction, .play)
            XCTAssertEqual(settings.rightClickAction, .menu)
            let reloaded = AppSettings(defaults: defaults)
            XCTAssertEqual(reloaded.leftClickAction, .play)
            XCTAssertEqual(reloaded.rightClickAction, .menu)
        }
    }

    @MainActor
    func testChoosingMenuSwapsPlayToTheOtherClickAndPersists() {
        withDefaults { defaults in
            let settings = AppSettings(defaults: defaults)

            settings.setLeftClickAction(.menu)
            var reloaded = AppSettings(defaults: defaults)
            XCTAssertEqual(reloaded.leftClickAction, .menu)
            XCTAssertEqual(reloaded.rightClickAction, .play)

            settings.setRightClickAction(.play)
            settings.setRightClickAction(.menu)
            reloaded = AppSettings(defaults: defaults)
            XCTAssertEqual(reloaded.leftClickAction, .play)
            XCTAssertEqual(reloaded.rightClickAction, .menu)
        }
    }

    @MainActor
    func testEveryClickChangeKeepsOnePlayAndOneMenuAction() {
        withDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            for leftAction in AppSettings.ClickAction.allCases {
                for rightAction in AppSettings.ClickAction.allCases {
                    settings.setLeftClickAction(leftAction)
                    XCTAssertEqual(settings.leftClickAction, leftAction)
                    XCTAssertNotEqual(settings.leftClickAction, settings.rightClickAction)

                    settings.setRightClickAction(rightAction)
                    XCTAssertEqual(settings.rightClickAction, rightAction)
                    XCTAssertNotEqual(settings.leftClickAction, settings.rightClickAction)
                }
            }
        }
    }

    @MainActor
    func testUnknownOrCorruptedStoredValuesFallBackToSafeDefaults() {
        withDefaults { defaults in
            let invalidValues: [Any] = ["unknown", "menuOnly", 42, ["unexpected"]]
            for invalidValue in invalidValues {
                defaults.set(invalidValue, forKey: "custom.menuBarContent")
                defaults.set(invalidValue, forKey: "custom.clickBehavior")
                defaults.set(true, forKey: "custom.acceptsMacros")

                let settings = AppSettings(defaults: defaults, storageKey: "custom")

                XCTAssertEqual(settings.menuBarContent, .xplay)
                XCTAssertEqual(settings.leftClickAction, .play)
                XCTAssertEqual(settings.rightClickAction, .menu)
                XCTAssertTrue(settings.acceptsMacros)
            }
        }
    }

    @MainActor
    func testMacroAcceptanceDefaultsOffAndPersistsGlobally() {
        let suiteName = "AppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let settings = AppSettings(defaults: defaults, storageKey: "settings")
        XCTAssertFalse(settings.acceptsMacros)

        settings.setAcceptsMacros(true)

        let reloadedSettings = AppSettings(defaults: defaults, storageKey: "settings")
        XCTAssertTrue(reloadedSettings.acceptsMacros)
    }

    @MainActor
    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suiteName = "AppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        body(defaults)
    }
}
