import Foundation
import XCTest
@testable import XPlay

final class ProjectCatalogTests: XCTestCase {
    @MainActor
    func testAddingXcodeProjectSelectsAndPersistsIt() {
        withDefaults { defaults in
            let projectURL = URL(fileURLWithPath: "/Projects/Example.xcodeproj")
            let catalog = ProjectCatalog(defaults: defaults, storageKey: "projects")

            XCTAssertTrue(catalog.add(projectURL))
            XCTAssertEqual(catalog.projects.map(\.name), ["Example"])
            XCTAssertEqual(catalog.selectedProject?.url, projectURL)

            let reloadedCatalog = ProjectCatalog(defaults: defaults, storageKey: "projects")

            XCTAssertEqual(reloadedCatalog.projects.map(\.url), [projectURL])
            XCTAssertEqual(reloadedCatalog.selectedProject?.url, projectURL)
        }
    }

    @MainActor
    func testAddingRejectsDuplicatesAndUnsupportedFiles() {
        withDefaults { defaults in
            let projectURL = URL(fileURLWithPath: "/Projects/Example.xcodeproj")
            let catalog = ProjectCatalog(defaults: defaults, storageKey: "projects")

            XCTAssertTrue(catalog.add(projectURL))
            XCTAssertFalse(catalog.add(projectURL))
            XCTAssertFalse(catalog.add(URL(fileURLWithPath: "/Projects/README.md")))
            XCTAssertEqual(catalog.projects.map(\.name), ["Example"])
        }
    }

    @MainActor
    func testRemovingSelectedProjectSelectsRemainingProject() {
        withDefaults { defaults in
            let firstURL = URL(fileURLWithPath: "/Projects/First.xcodeproj")
            let secondURL = URL(fileURLWithPath: "/Projects/Second.xcodeproj")
            let catalog = ProjectCatalog(defaults: defaults, storageKey: "projects")
            catalog.add(firstURL)
            catalog.add(secondURL)
            catalog.selectProject(at: 0)

            XCTAssertTrue(catalog.removeProject(at: 0))
            XCTAssertEqual(catalog.projects.map(\.url), [secondURL])
            XCTAssertEqual(catalog.selectedProject?.url, secondURL)
        }
    }

    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suiteName = "ProjectCatalogTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        body(defaults)
    }
}
