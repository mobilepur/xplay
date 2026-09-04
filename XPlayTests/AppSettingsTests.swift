import Foundation
import XCTest
@testable import XPlay

final class AppSettingsTests: XCTestCase {
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
}
