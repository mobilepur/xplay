import Foundation
import XCTest
@testable import XPlay

final class ProjectCatalogTests: XCTestCase {
    @MainActor
    func testAddingWorkspacePersistsLaunchConfigurations() {
        withDefaults { defaults in
            let workspaceURL = URL(fileURLWithPath: "/Projects/Example.xcworkspace")
            let catalog = ProjectCatalog(defaults: defaults, storageKey: "projects")

            XCTAssertTrue(catalog.add(workspaceURL, schemes: ["Example-macOS", "Example-iOS"]))
            XCTAssertEqual(catalog.projects.map(\.name), ["Example"])
            XCTAssertEqual(catalog.selectedProject?.url, workspaceURL)
            XCTAssertEqual(catalog.selectedProject?.kind, .workspace)
            XCTAssertEqual(
                catalog.selectedProject?.configurations,
                [
                    LaunchConfiguration(scheme: "Example-macOS"),
                    LaunchConfiguration(scheme: "Example-iOS"),
                ]
            )

            let reloadedCatalog = ProjectCatalog(defaults: defaults, storageKey: "projects")

            XCTAssertEqual(reloadedCatalog.projects, catalog.projects)
            XCTAssertEqual(reloadedCatalog.selectedProject?.url, workspaceURL)
        }
    }

    @MainActor
    func testAddingRejectsDuplicatesAndUnsupportedFiles() {
        withDefaults { defaults in
            let workspaceURL = URL(fileURLWithPath: "/Projects/Example.xcworkspace")
            let catalog = ProjectCatalog(defaults: defaults, storageKey: "projects")

            XCTAssertTrue(catalog.add(workspaceURL))
            XCTAssertFalse(catalog.add(workspaceURL))
            XCTAssertFalse(catalog.add(URL(fileURLWithPath: "/Projects/README.md")))
            XCTAssertEqual(catalog.projects.map(\.name), ["Example"])
        }
    }

    @MainActor
    func testRemovingSelectedProjectSelectsRemainingProject() {
        withDefaults { defaults in
            let firstURL = URL(fileURLWithPath: "/Projects/First.xcworkspace")
            let secondURL = URL(fileURLWithPath: "/Projects/Second.xcworkspace")
            let catalog = ProjectCatalog(defaults: defaults, storageKey: "projects")
            catalog.add(firstURL)
            catalog.add(secondURL)
            catalog.selectProject(at: 0)

            XCTAssertTrue(catalog.removeProject(at: 0))
            XCTAssertEqual(catalog.projects.map(\.url), [secondURL])
            XCTAssertEqual(catalog.selectedProject?.url, secondURL)
        }
    }

    @MainActor
    func testEnablingSchemeAndSelectingDestinationPersists() {
        withDefaults { defaults in
            let workspaceURL = URL(fileURLWithPath: "/Projects/Example.xcworkspace")
            let mac = XcodeDestination(platform: .macOS, id: "mac-id", name: "My Mac")
            let catalog = ProjectCatalog(defaults: defaults, storageKey: "projects")
            catalog.add(workspaceURL, schemes: ["Example-macOS", "Example-iOS"])

            catalog.setSchemeEnabled(true, scheme: "Example-macOS", forProjectAt: 0)
            catalog.updateDestinations([mac], scheme: "Example-macOS", forProjectAt: 0)

            XCTAssertEqual(catalog.selectedProject?.enabledConfigurations.count, 1)
            XCTAssertEqual(
                catalog.selectedProject?.enabledConfigurations.first?.selectedDestination,
                mac
            )

            let reloadedCatalog = ProjectCatalog(defaults: defaults, storageKey: "projects")

            XCTAssertEqual(reloadedCatalog.selectedProject?.enabledConfigurations.count, 1)
            XCTAssertEqual(
                reloadedCatalog.selectedProject?.enabledConfigurations.first?.selectedDestination,
                mac
            )
        }
    }

    @MainActor
    func testRefreshingSchemesPreservesMatchingConfiguration() {
        withDefaults { defaults in
            let workspaceURL = URL(fileURLWithPath: "/Projects/Example.xcworkspace")
            let mac = XcodeDestination(platform: .macOS, id: "mac-id", name: "My Mac")
            let catalog = ProjectCatalog(defaults: defaults, storageKey: "projects")
            catalog.add(workspaceURL, schemes: ["Old", "Selected"])
            catalog.setSchemeEnabled(true, scheme: "Selected", forProjectAt: 0)
            catalog.updateDestinations([mac], scheme: "Selected", forProjectAt: 0)

            catalog.updateSchemes(["Selected", "New"], forProjectAt: 0)

            XCTAssertEqual(catalog.projects[0].schemes, ["Selected", "New"])
            XCTAssertEqual(catalog.projects[0].configurations[0].selectedDestination, mac)
            XCTAssertTrue(catalog.projects[0].configurations[0].isEnabled)
            XCTAssertFalse(catalog.projects[0].configurations[1].isEnabled)
        }
    }

    @MainActor
    func testDestinationRefreshDoesNotSilentlyReplaceUnavailableSelection() {
        withDefaults { defaults in
            let workspaceURL = URL(fileURLWithPath: "/Projects/Example.xcworkspace")
            let oldMac = XcodeDestination(platform: .macOS, id: "old", name: "Old Mac")
            let newMac = XcodeDestination(platform: .macOS, id: "new", name: "New Mac")
            let simulator = XcodeDestination(
                platform: .iOSSimulator,
                id: "sim",
                name: "iPhone 17 Pro",
                osVersion: "26.0"
            )
            let catalog = ProjectCatalog(defaults: defaults, storageKey: "projects")
            catalog.add(workspaceURL, schemes: ["Example"])
            catalog.updateDestinations([oldMac, simulator], scheme: "Example", forProjectAt: 0)
            catalog.selectDestination(id: "old", scheme: "Example", forProjectAt: 0)

            catalog.updateDestinations([newMac, simulator], scheme: "Example", forProjectAt: 0)

            XCTAssertEqual(
                catalog.projects[0].configurations[0].selectedDestination,
                oldMac
            )
            XCTAssertFalse(
                catalog.projects[0].configurations[0].isSelectedDestinationAvailable
            )
            XCTAssertEqual(
                catalog.projects[0].configurations[0].availableDestinations,
                [newMac, simulator]
            )
        }
    }

    @MainActor
    func testMigratesLegacyXcodeProjectAndDoesNotPromoteMacroConsent() {
        withDefaults { defaults in
            let path = "/Projects/Legacy.xcodeproj"
            defaults.set([path], forKey: "projects")
            defaults.set(path, forKey: "projects.selected")
            defaults.set([path: ["Legacy", "LegacyTests"]], forKey: "projects.schemes")
            defaults.set([path: "LegacyTests"], forKey: "projects.selectedSchemes")
            defaults.set([path], forKey: "projects.acceptedMacros")

            let catalog = ProjectCatalog(defaults: defaults, storageKey: "projects")

            XCTAssertEqual(catalog.selectedProject?.kind, .project)
            XCTAssertEqual(catalog.selectedProject?.enabledConfigurations.map(\.scheme), ["LegacyTests"])
            XCTAssertFalse(AppSettings(defaults: defaults, storageKey: "settings").acceptsMacros)

            let reloadedCatalog = ProjectCatalog(defaults: defaults, storageKey: "projects")
            XCTAssertEqual(reloadedCatalog.projects, catalog.projects)
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
