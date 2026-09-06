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
    func testSelectedLaunchConfigurationPersistsAndFallsBackWhenDisabled() {
        withDefaults { defaults in
            let workspaceURL = URL(fileURLWithPath: "/Projects/Example.xcworkspace")
            let catalog = ProjectCatalog(defaults: defaults, storageKey: "projects")
            catalog.add(workspaceURL, schemes: ["Example-macOS", "Example-iOS"])
            catalog.setSchemeEnabled(true, scheme: "Example-macOS", forProjectAt: 0)
            catalog.setSchemeEnabled(true, scheme: "Example-iOS", forProjectAt: 0)

            XCTAssertEqual(
                catalog.selectedProject?.selectedLaunchConfiguration?.scheme,
                "Example-macOS"
            )

            catalog.selectLaunchConfiguration(scheme: "Example-iOS", forProjectAt: 0)

            XCTAssertEqual(
                catalog.selectedProject?.selectedLaunchConfiguration?.scheme,
                "Example-iOS"
            )
            XCTAssertEqual(
                ProjectCatalog(defaults: defaults, storageKey: "projects")
                    .selectedProject?.selectedLaunchConfiguration?.scheme,
                "Example-iOS"
            )

            catalog.setSchemeEnabled(false, scheme: "Example-iOS", forProjectAt: 0)

            XCTAssertEqual(
                catalog.selectedProject?.selectedLaunchConfiguration?.scheme,
                "Example-macOS"
            )
        }
    }

    @MainActor
    func testExistingWorkspaceRecordSelectsFirstEnabledConfiguration() throws {
        try withDefaults { defaults in
            let workspaceURL = URL(fileURLWithPath: "/Projects/Example.xcworkspace")
            let previousRecord = PreviouslySavedProject(
                url: workspaceURL,
                kind: .workspace,
                configurations: [
                    LaunchConfiguration(scheme: "Disabled"),
                    LaunchConfiguration(scheme: "Enabled", isEnabled: true),
                ]
            )
            defaults.set(
                try JSONEncoder().encode([previousRecord]),
                forKey: "projects.records.v2"
            )
            defaults.set(workspaceURL.path, forKey: "projects.selected")

            let catalog = ProjectCatalog(defaults: defaults, storageKey: "projects")

            XCTAssertEqual(
                catalog.selectedProject?.selectedLaunchConfiguration?.scheme,
                "Enabled"
            )
            XCTAssertNil(catalog.selectedProject?.selectedWorkingCopyURL)
            XCTAssertEqual(catalog.selectedProject?.activeContainerURL, workspaceURL)
            XCTAssertEqual(
                ProjectCatalog(defaults: defaults, storageKey: "projects").projects,
                catalog.projects
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

    @MainActor
    func testSelectingWorkingCopyPersistsNormalizesAndResetsToOriginal() throws {
        try withDefaults { defaults in
            let originalURL = URL(fileURLWithPath: "/Projects/Example.xcworkspace")
            let worktreeURL = URL(fileURLWithPath: "/Worktrees/feature/Example.xcworkspace")
            let catalog = ProjectCatalog(defaults: defaults, storageKey: "projects")
            catalog.add(originalURL, schemes: ["Example", "Other"])
            catalog.selectWorkingCopy(
                containerURL: URL(fileURLWithPath: "/Worktrees/unused/../feature/Example.xcworkspace"),
                forProjectAt: 0
            )
            XCTAssertEqual(catalog.selectedProject?.selectedWorkingCopyURL, worktreeURL)
            XCTAssertEqual(catalog.selectedProject?.activeContainerURL, worktreeURL)
            XCTAssertEqual(catalog.selectedProject?.url, originalURL)
            XCTAssertEqual(catalog.selectedProject?.name, "Example")

            let mac = XcodeDestination(platform: .macOS, id: "mac", name: "My Mac")
            catalog.updateSchemes(["Example", "Other", "New"], forProjectAt: 0)
            catalog.setSchemeEnabled(true, scheme: "Example", forProjectAt: 0)
            catalog.setSchemeEnabled(true, scheme: "Other", forProjectAt: 0)
            catalog.updateDestinations([mac], scheme: "Other", forProjectAt: 0)
            catalog.selectDestination(id: mac.id, scheme: "Other", forProjectAt: 0)
            catalog.selectLaunchConfiguration(scheme: "Other", forProjectAt: 0)
            catalog.add(URL(fileURLWithPath: "/Projects/Second.xcodeproj"))
            catalog.selectProject(at: 0)
            catalog.removeProject(at: 1)
            let reloaded = ProjectCatalog(defaults: defaults, storageKey: "projects")
            let selected = try XCTUnwrap(reloaded.selectedProject)
            XCTAssertEqual(selected.activeContainerURL, worktreeURL)
            XCTAssertEqual(selected.selectedLaunchConfiguration?.scheme, "Other")
            XCTAssertEqual(selected.selectedLaunchConfiguration?.selectedDestination, mac)

            reloaded.selectWorkingCopy(containerURL: nil, forProjectAt: 0)
            let reset = ProjectCatalog(defaults: defaults, storageKey: "projects")
            XCTAssertNil(reset.selectedProject?.selectedWorkingCopyURL)
            XCTAssertEqual(reset.selectedProject?.activeContainerURL, originalURL)
            XCTAssertEqual(reset.selectedProject?.selectedLaunchConfiguration?.scheme, "Other")
        }
    }

    @MainActor
    func testSelectingWorkingCopyRejectsWrongContainerKindAndInvalidIndex() {
        withDefaults { defaults in
            let originalURL = URL(fileURLWithPath: "/Projects/Example.xcworkspace")
            let worktreeURL = URL(fileURLWithPath: "/Worktrees/feature/Example.xcworkspace")
            let catalog = ProjectCatalog(defaults: defaults, storageKey: "projects")
            catalog.add(originalURL)
            catalog.selectWorkingCopy(containerURL: worktreeURL, forProjectAt: 0)

            catalog.selectWorkingCopy(
                containerURL: URL(fileURLWithPath: "/Worktrees/feature/Example.xcodeproj"),
                forProjectAt: 0
            )
            catalog.selectWorkingCopy(containerURL: nil, forProjectAt: -1)
            catalog.selectWorkingCopy(containerURL: nil, forProjectAt: 1)

            XCTAssertEqual(catalog.selectedProject?.activeContainerURL, worktreeURL)
            XCTAssertEqual(
                ProjectCatalog(defaults: defaults, storageKey: "projects")
                    .selectedProject?.selectedWorkingCopyURL,
                worktreeURL
            )
        }
    }

    func testSavedProjectDefaultsToOriginalContainerAndNormalizesSelectedWorkingCopy() {
        let originalURL = URL(fileURLWithPath: "/Projects/Example.xcodeproj")
        XCTAssertEqual(SavedProject(url: originalURL, kind: .project).activeContainerURL, originalURL)
        let selected = SavedProject(
            url: originalURL,
            kind: .project,
            selectedWorkingCopyURL: URL(fileURLWithPath: "/Worktrees/unused/../feature/Example.xcodeproj")
        )
        XCTAssertEqual(selected.activeContainerURL.path, "/Worktrees/feature/Example.xcodeproj")
        XCTAssertEqual(selected.url, originalURL)
    }

    @MainActor
    func testStoredWorkingCopySurvivesCatalogReloadAndMutation() throws {
        try withDefaults { defaults in
            let originalURL = URL(fileURLWithPath: "/Projects/Example.xcworkspace")
            let worktreeURL = URL(fileURLWithPath: "/Worktrees/feature/Example.xcworkspace")
            let original = SavedProject(url: originalURL, kind: .workspace)
            var record = try XCTUnwrap(JSONSerialization.jsonObject(
                with: JSONEncoder().encode(original)
            ) as? [String: Any])
            record["selectedWorkingCopyURL"] = URL(
                fileURLWithPath: "/Worktrees/unused/../feature/Example.xcworkspace"
            ).absoluteString
            defaults.set(try JSONSerialization.data(withJSONObject: [record]), forKey: "projects.records.v2")
            defaults.set(originalURL.path, forKey: "projects.selected")

            let catalog = ProjectCatalog(defaults: defaults, storageKey: "projects")
            catalog.updateSchemes(["Example"], forProjectAt: 0)
            catalog.setSchemeEnabled(true, scheme: "Example", forProjectAt: 0)
            let reloaded = ProjectCatalog(defaults: defaults, storageKey: "projects")
            let saved = try XCTUnwrap(reloaded.selectedProject)
            let encoded = try XCTUnwrap(JSONSerialization.jsonObject(
                with: JSONEncoder().encode(saved)
            ) as? [String: Any])

            XCTAssertEqual(saved.url, originalURL)
            XCTAssertEqual(saved.name, "Example")
            XCTAssertEqual(encoded["selectedWorkingCopyURL"] as? String, worktreeURL.absoluteString)
            XCTAssertEqual(saved.selectedLaunchConfiguration?.scheme, "Example")
        }
    }

    private struct PreviouslySavedProject: Encodable {
        let url: URL
        let kind: XcodeContainerKind
        let configurations: [LaunchConfiguration]
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let suiteName = "ProjectCatalogTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        try body(defaults)
    }
}
