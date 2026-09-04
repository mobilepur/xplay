import AppKit
import Foundation
import XCTest
@testable import XPlay

final class StatusBarControllerTests: XCTestCase {
    @MainActor
    func testRightMouseUpMapsToContextMenu() {
        XCTAssertEqual(
            StatusBarController.interaction(for: .rightMouseUp),
            .showContextMenu
        )
    }

    @MainActor
    func testContextMenuShowsProjectsSettingsAndQuitSections() throws {
        var didRequestProjectEditor = false
        let controller = StatusBarController(
            onEditProjects: { didRequestProjectEditor = true }
        )
        let items = controller.contextMenu.items

        XCTAssertEqual(
            items.map(\.title),
            [
                "No project selected",
                "",
                "Projects", "No projects yet",
                "",
                "Settings", "Accept Macros",
                "",
                "Quit",
            ]
        )
        let projectsHeader = try XCTUnwrap(items.first { $0.title == "Projects" }?.view)
        let editButton = try XCTUnwrap(
            projectsHeader.subviews.compactMap { $0 as? NSButton }.first
        )
        XCTAssertEqual(editButton.title, "Edit")
        editButton.performClick(nil)
        XCTAssertTrue(didRequestProjectEditor)
        XCTAssertEqual(items.first { $0.title == "Quit" }?.keyEquivalent, "q")
    }

    @MainActor
    func testSelectedProjectListsEnabledSchemesAndDestinations() throws {
        withState { catalog, settings in
            let mac = XcodeDestination(platform: .macOS, id: "mac", name: "My Mac")
            let simulator = XcodeDestination(
                platform: .iOSSimulator,
                id: "sim",
                name: "iPhone 17 Pro",
                osVersion: "26.0"
            )
            configure(
                catalog,
                schemes: ["Example-macOS", "Example-iOS"],
                destinations: [[mac], [simulator]]
            )

            let controller = StatusBarController(
                projectCatalog: catalog,
                appSettings: settings
            )
            let items = controller.contextMenu.items

            XCTAssertEqual(
                Array(items.prefix(3)).map(\.title),
                [
                    "Example",
                    "Example-macOS — My Mac",
                    "Example-iOS — iPhone 17 Pro (26.0)",
                ]
            )
            XCTAssertEqual(items[1].submenu?.items.map(\.title), ["My Mac"])
            XCTAssertEqual(items[1].submenu?.items.first?.state, .on)
            XCTAssertEqual(items[2].submenu?.items.map(\.title), ["iPhone 17 Pro (26.0)"])
        }
    }

    @MainActor
    func testSelectingDestinationFromSchemeSubmenuPersistsSelection() throws {
        try withState { catalog, settings in
            let first = XcodeDestination(
                platform: .iOSSimulator,
                id: "first",
                name: "iPhone 17"
            )
            let second = XcodeDestination(
                platform: .iOSSimulator,
                id: "second",
                name: "iPhone 17 Pro"
            )
            configure(catalog, schemes: ["Example-iOS"], destinations: [[first, second]])
            let controller = StatusBarController(
                projectCatalog: catalog,
                appSettings: settings
            )
            let schemeItem = try XCTUnwrap(
                controller.contextMenu.items.first { $0.title.hasPrefix("Example-iOS") }
            )
            let submenu = try XCTUnwrap(schemeItem.submenu)

            submenu.performActionForItem(at: 1)

            XCTAssertEqual(
                catalog.selectedProject?.enabledConfigurations.first?.selectedDestination,
                second
            )
        }
    }

    @MainActor
    func testAcceptMacrosIsGlobalAndRequiresConfirmationWhenEnabled() throws {
        try withState { catalog, settings in
            var confirmationCount = 0
            let controller = StatusBarController(
                projectCatalog: catalog,
                appSettings: settings,
                confirmMacroAcceptance: {
                    confirmationCount += 1
                    return true
                }
            )
            let item = try XCTUnwrap(
                controller.contextMenu.items.first { $0.title == "Accept Macros" }
            )
            let menu = try XCTUnwrap(item.menu)

            XCTAssertEqual(item.state, .off)
            menu.performActionForItem(at: menu.index(of: item))

            XCTAssertTrue(settings.acceptsMacros)
            XCTAssertEqual(confirmationCount, 1)
            XCTAssertEqual(StatusBarController.macroWarningText, "Accept Macros skips Xcode validation for all current and future macros in every XPlay project.")
        }
    }

    @MainActor
    func testStatusItemRequiresEveryEnabledSchemeToHaveDestination() {
        withState { catalog, settings in
            configure(catalog, schemes: ["Example"], destinations: [[]])
            let controller = StatusBarController(
                projectCatalog: catalog,
                appSettings: settings
            )

            XCTAssertEqual(
                controller.statusItem.button?.accessibilityLabel(),
                "Choose a destination for every enabled scheme. Right-click for menu"
            )

            let mac = XcodeDestination(platform: .macOS, id: "mac", name: "My Mac")
            catalog.updateDestinations([mac], scheme: "Example", forProjectAt: 0)
            controller.refreshConfiguration()

            XCTAssertEqual(controller.statusItem.button?.accessibilityLabel(), "Start project")
        }
    }

    @MainActor
    func testStartingProjectLaunchesEveryConfigurationSequentiallyAfterFailure() async {
        let suiteName = "StatusBarControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let catalog = ProjectCatalog(defaults: defaults, storageKey: "projects")
        let settings = AppSettings(defaults: defaults, storageKey: "settings")
        settings.setAcceptsMacros(true)
        let mac = XcodeDestination(platform: .macOS, id: "mac", name: "My Mac")
        let simulator = XcodeDestination(
            platform: .iOSSimulator,
            id: "sim",
            name: "iPhone 17 Pro"
        )
        configure(
            catalog,
            schemes: ["Example-macOS", "Example-iOS"],
            destinations: [[mac], [simulator]]
        )
        let finished = expectation(description: "All launch configurations finished")
        var receivedPlans: [XcodeProjectLaunchPlan] = []
        var receivedFailures: [StatusBarController.LaunchFailure] = []
        let controller = StatusBarController(
            projectCatalog: catalog,
            appSettings: settings,
            cacheDirectory: URL(fileURLWithPath: "/Caches/XPlay"),
            makeLauncher: { plan in
                receivedPlans.append(plan)
                let result: Result<URL, Error> = plan.scheme == "Example-macOS"
                    ? .failure(TestLaunchError.failed)
                    : .success(URL(fileURLWithPath: "/tmp/Example.app"))
                return RecordingProjectLauncher(logURL: plan.logURL, result: result)
            },
            presentLaunchFailures: { failures in
                receivedFailures = failures
                finished.fulfill()
            }
        )

        controller.perform(.startProject)
        await fulfillment(of: [finished], timeout: 2)

        XCTAssertEqual(receivedPlans.map(\.scheme), ["Example-macOS", "Example-iOS"])
        XCTAssertTrue(receivedPlans.allSatisfy(\.acceptsMacros))
        XCTAssertEqual(receivedFailures.map(\.plan.scheme), ["Example-macOS"])
        XCTAssertEqual(controller.statusItem.button?.accessibilityLabel(), "Start project")
    }

    @MainActor
    func testRunningStatusNamesCurrentConfigurationAndPosition() {
        withState { catalog, settings in
            let mac = XcodeDestination(platform: .macOS, id: "mac", name: "My Mac")
            let simulator = XcodeDestination(
                platform: .iOSSimulator,
                id: "sim",
                name: "iPhone 17 Pro"
            )
            configure(
                catalog,
                schemes: ["Example-macOS", "Example-iOS"],
                destinations: [[mac], [simulator]]
            )
            let launcher = DeferredProjectLauncher()
            let controller = StatusBarController(
                projectCatalog: catalog,
                appSettings: settings,
                makeLauncher: { _ in launcher }
            )

            controller.perform(.startProject)

            XCTAssertEqual(
                controller.statusItem.button?.accessibilityLabel(),
                "Starting Example-macOS (1 of 2)"
            )
            XCTAssertEqual(
                controller.statusItem.button?.toolTip,
                "Building and launching Example-macOS (1 of 2)…"
            )
        }
    }

    @MainActor
    func testStatusProjectSelectionSynchronizesOpenEditorAndActionsTargetVisibleProject() async throws {
        let suiteName = "StatusBarControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let catalog = ProjectCatalog(defaults: defaults, storageKey: "projects")
        catalog.add(
            URL(fileURLWithPath: "/Projects/First.xcworkspace"),
            schemes: ["FirstScheme"]
        )
        catalog.add(
            URL(fileURLWithPath: "/Projects/Second.xcworkspace"),
            schemes: ["SecondScheme"]
        )
        catalog.selectProject(at: 0)
        let resolver = XcodeSchemeResolver { arguments in
            if arguments.first == "-showdestinations" {
                return Data("{ platform:macOS, id:mac, name:My Mac }".utf8)
            }
            return Data("{\"workspace\":{\"schemes\":[]}}".utf8)
        }
        let editor = ProjectWindowController(catalog: catalog, schemeResolver: resolver)
        editor.loadWindow()
        let controller = StatusBarController(
            projectCatalog: catalog,
            appSettings: AppSettings(defaults: defaults, storageKey: "settings"),
            onCatalogChange: { editor.refreshFromCatalog() }
        )
        let secondProjectItem = try XCTUnwrap(
            controller.contextMenu.items.first {
                $0.title == "Second" && $0.action != nil
            }
        )
        let menu = try XCTUnwrap(secondProjectItem.menu)

        menu.performActionForItem(at: menu.index(of: secondProjectItem))

        XCTAssertEqual(editor.projectTableView.selectedRow, 1)
        XCTAssertEqual(editor.schemeTableView.numberOfRows, 1)
        let schemeCell = try XCTUnwrap(
            editor.tableView(
                editor.schemeTableView,
                viewFor: editor.schemeTableView.tableColumns[0],
                row: 0
            )
        )
        let checkbox = try XCTUnwrap(
            schemeCell.subviews.compactMap { $0 as? NSButton }.first
        )
        XCTAssertEqual(checkbox.title, "SecondScheme")

        checkbox.performClick(nil)
        await Task.yield()
        await Task.yield()

        XCTAssertFalse(catalog.projects[0].configurations[0].isEnabled)
        XCTAssertTrue(catalog.projects[1].configurations[0].isEnabled)
    }

    @MainActor
    private func configure(
        _ catalog: ProjectCatalog,
        schemes: [String],
        destinations: [[XcodeDestination]]
    ) {
        catalog.add(
            URL(fileURLWithPath: "/Projects/Example.xcworkspace"),
            schemes: schemes
        )
        for (scheme, availableDestinations) in zip(schemes, destinations) {
            catalog.setSchemeEnabled(true, scheme: scheme, forProjectAt: 0)
            catalog.updateDestinations(
                availableDestinations,
                scheme: scheme,
                forProjectAt: 0
            )
        }
    }

    @MainActor
    private func withState(
        _ body: (ProjectCatalog, AppSettings) throws -> Void
    ) rethrows {
        let suiteName = "StatusBarControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(
            ProjectCatalog(defaults: defaults, storageKey: "projects"),
            AppSettings(defaults: defaults, storageKey: "settings")
        )
    }
}

private enum TestLaunchError: Error {
    case failed
}

private final class RecordingProjectLauncher: ProjectLaunching, @unchecked Sendable {
    let logURL: URL
    private let result: Result<URL, Error>

    init(logURL: URL, result: Result<URL, Error>) {
        self.logURL = logURL
        self.result = result
    }

    func launch(completion: @escaping @Sendable (Result<URL, Error>) -> Void) {
        completion(result)
    }
}

private final class DeferredProjectLauncher: ProjectLaunching, @unchecked Sendable {
    let logURL = URL(fileURLWithPath: "/tmp/deferred-build.log")

    func launch(completion: @escaping @Sendable (Result<URL, Error>) -> Void) {}
}
