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
                    "Example-macOS",
                    "Example-iOS",
                ]
            )
            XCTAssertEqual(
                items[1].submenu?.items.map(\.title),
                ["Use for Play", "", "My Mac"]
            )
            XCTAssertEqual(
                items[2].submenu?.items.map(\.title),
                ["Use for Play", "", "iPhone 17 Pro (26.0)"]
            )
            XCTAssertEqual(
                items[1].submenu?.items.first { $0.title == "My Mac" }?.state,
                .on
            )
            XCTAssertEqual(items[1].state, .on)
            XCTAssertEqual(items[2].state, .off)
        }
    }

    @MainActor
    func testConfigurationRowsUseFlexibleSchemeDestinationAndChevronLayout() throws {
        try withState { catalog, settings in
            let simulator = XcodeDestination(
                platform: .iOSSimulator,
                id: "sim",
                name: "iPhone 17 Pro",
                osVersion: "26.0"
            )
            configure(
                catalog,
                schemes: ["Example-iOS"],
                destinations: [[simulator]]
            )
            let controller = StatusBarController(
                projectCatalog: catalog,
                appSettings: settings
            )
            let item = controller.contextMenu.items[1]
            let row = try XCTUnwrap(item.view)
            let labels = row.subviews.compactMap { $0 as? NSTextField }
            let schemeLabel = try XCTUnwrap(
                labels.first { $0.stringValue == "Example-iOS" }
            )
            let destinationLabel = try XCTUnwrap(
                labels.first { $0.stringValue == "iPhone 17 Pro (26.0)" }
            )
            let imageViews = row.subviews.compactMap { $0 as? NSImageView }
            let checkmark = try XCTUnwrap(
                imageViews.first { $0.identifier?.rawValue == "configuration-checkmark" }
            )
            let chevron = try XCTUnwrap(
                imageViews.first { $0.identifier?.rawValue == "configuration-chevron" }
            )
            row.frame.size.width = 360
            row.layoutSubtreeIfNeeded()
            let destinationAlignmentRect = destinationLabel.alignmentRect(
                forFrame: destinationLabel.frame
            )
            let chevronAlignmentRect = chevron.alignmentRect(forFrame: chevron.frame)

            XCTAssertNil(item.attributedTitle)
            XCTAssertEqual(destinationLabel.textColor, .secondaryLabelColor)
            XCTAssertFalse(checkmark.isHidden)
            XCTAssertLessThan(schemeLabel.frame.maxX, destinationLabel.frame.minX)
            XCTAssertEqual(
                chevronAlignmentRect.minX - destinationAlignmentRect.maxX,
                8,
                accuracy: 0.5
            )
            XCTAssertEqual(row.frame.maxX - chevron.frame.maxX, 12, accuracy: 0.5)
            XCTAssertNotNil(item.submenu)
            XCTAssertEqual(
                item.accessibilityLabel(),
                "Example-iOS, iPhone 17 Pro (26.0)"
            )
        }
    }

    @MainActor
    func testConfigurationRowPreservesSchemeWhenDestinationIsLong() throws {
        try withState { catalog, settings in
            let simulator = XcodeDestination(
                platform: .iOSSimulator,
                id: "sim",
                name: "iPhone 17 Pro Max with an exceptionally long destination name",
                osVersion: "26.0"
            )
            configure(
                catalog,
                schemes: ["Example-iOS"],
                destinations: [[simulator]]
            )
            let controller = StatusBarController(
                projectCatalog: catalog,
                appSettings: settings
            )
            let row = try XCTUnwrap(controller.contextMenu.items[1].view)
            let labels = row.subviews.compactMap { $0 as? NSTextField }
            let schemeLabel = try XCTUnwrap(
                labels.first { $0.stringValue == "Example-iOS" }
            )
            let destinationLabel = try XCTUnwrap(
                labels.first { $0.stringValue.hasPrefix("iPhone 17 Pro Max") }
            )
            row.frame.size.width = 320
            row.layoutSubtreeIfNeeded()

            XCTAssertEqual(row.frame.width, 320, accuracy: 0.5)
            XCTAssertGreaterThanOrEqual(
                schemeLabel.frame.width,
                schemeLabel.intrinsicContentSize.width - 0.5
            )
            XCTAssertLessThan(
                destinationLabel.frame.width,
                destinationLabel.intrinsicContentSize.width
            )
        }
    }

    @MainActor
    func testConfigurationRowTracksMenuHighlightAppearance() throws {
        try withState { catalog, settings in
            let simulator = XcodeDestination(
                platform: .iOSSimulator,
                id: "sim",
                name: "iPhone 17 Pro"
            )
            configure(
                catalog,
                schemes: ["Example-iOS"],
                destinations: [[simulator]]
            )
            let controller = StatusBarController(
                projectCatalog: catalog,
                appSettings: settings
            )
            let menu = controller.contextMenu
            let item = menu.items[1]
            let row = try XCTUnwrap(item.view)
            let labels = row.subviews.compactMap { $0 as? NSTextField }
            let schemeLabel = try XCTUnwrap(
                labels.first { $0.stringValue == "Example-iOS" }
            )
            let destinationLabel = try XCTUnwrap(
                labels.first { $0.stringValue == "iPhone 17 Pro" }
            )

            XCTAssertNotNil(menu.delegate)
            menu.delegate?.menu?(menu, willHighlight: item)

            XCTAssertEqual(schemeLabel.textColor, .selectedMenuItemTextColor)
            XCTAssertEqual(destinationLabel.textColor, .selectedMenuItemTextColor)

            menu.delegate?.menu?(menu, willHighlight: nil)

            XCTAssertEqual(schemeLabel.textColor, .labelColor)
            XCTAssertEqual(destinationLabel.textColor, .secondaryLabelColor)
        }
    }

    @MainActor
    func testSelectingSchemeForPlayUpdatesMenuSelection() throws {
        try withState { catalog, settings in
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
            let controller = StatusBarController(
                projectCatalog: catalog,
                appSettings: settings
            )
            let iosItem = try XCTUnwrap(
                controller.contextMenu.items.first { $0.title.hasPrefix("Example-iOS") }
            )
            let useForPlayItem = try XCTUnwrap(
                iosItem.submenu?.items.first { $0.title == "Use for Play" }
            )
            let submenu = try XCTUnwrap(useForPlayItem.menu)

            submenu.performActionForItem(at: submenu.index(of: useForPlayItem))

            XCTAssertEqual(
                catalog.selectedProject?.selectedLaunchConfiguration?.scheme,
                "Example-iOS"
            )
            let refreshedSchemes = controller.contextMenu.items.filter {
                $0.title.hasPrefix("Example-")
            }
            XCTAssertEqual(refreshedSchemes.map(\.state), [.off, .on])
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
            let secondDestination = try XCTUnwrap(
                submenu.items.first { $0.title == "iPhone 17 Pro" }
            )

            submenu.performActionForItem(at: submenu.index(of: secondDestination))

            XCTAssertEqual(
                catalog.selectedProject?.enabledConfigurations.first?.selectedDestination,
                second
            )
            XCTAssertEqual(
                catalog.selectedProject?.selectedLaunchConfiguration?.scheme,
                "Example-iOS"
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
            let row = try XCTUnwrap(item.view)
            let label = try XCTUnwrap(
                row.subviews.compactMap { $0 as? NSTextField }.first
            )
            let toggle = try XCTUnwrap(
                row.subviews.compactMap { $0 as? NSSwitch }.first
            )
            row.layoutSubtreeIfNeeded()

            XCTAssertEqual(label.stringValue, "Accept Macros")
            XCTAssertGreaterThan(toggle.frame.minX, label.frame.maxX)
            XCTAssertEqual(toggle.state, .off)
            XCTAssertEqual(toggle.accessibilityLabel(), "Accept Macros")
            XCTAssertEqual(toggle.toolTip, StatusBarController.macroWarningText)
            toggle.performClick(nil)

            XCTAssertTrue(settings.acceptsMacros)
            XCTAssertEqual(confirmationCount, 1)
            XCTAssertEqual(StatusBarController.macroWarningText, "Accept Macros skips Xcode validation for all current and future macros in every XPlay project.")
        }
    }

    @MainActor
    func testCancellingMacroAcceptanceLeavesSwitchOff() throws {
        try withState { catalog, settings in
            let controller = StatusBarController(
                projectCatalog: catalog,
                appSettings: settings,
                confirmMacroAcceptance: { false }
            )
            let item = try XCTUnwrap(
                controller.contextMenu.items.first { $0.title == "Accept Macros" }
            )
            let row = try XCTUnwrap(item.view)
            let toggle = try XCTUnwrap(
                row.subviews.compactMap { $0 as? NSSwitch }.first
            )

            toggle.performClick(nil)

            XCTAssertEqual(toggle.state, .off)
            XCTAssertFalse(settings.acceptsMacros)
        }
    }

    @MainActor
    func testEnabledMacroSwitchCanBeDisabledWithoutConfirmation() throws {
        try withState { catalog, settings in
            settings.setAcceptsMacros(true)
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
            let row = try XCTUnwrap(item.view)
            let toggle = try XCTUnwrap(
                row.subviews.compactMap { $0 as? NSSwitch }.first
            )

            XCTAssertEqual(toggle.state, .on)
            toggle.performClick(nil)

            XCTAssertFalse(settings.acceptsMacros)
            XCTAssertEqual(confirmationCount, 0)
        }
    }

    @MainActor
    func testStatusItemRequiresSelectedSchemeToHaveDestination() {
        withState { catalog, settings in
            configure(catalog, schemes: ["Example"], destinations: [[]])
            let controller = StatusBarController(
                projectCatalog: catalog,
                appSettings: settings
            )

            XCTAssertEqual(
                controller.statusItem.button?.accessibilityLabel(),
                "Choose a destination for the selected scheme. Right-click for menu"
            )

            let mac = XcodeDestination(platform: .macOS, id: "mac", name: "My Mac")
            catalog.updateDestinations([mac], scheme: "Example", forProjectAt: 0)
            controller.refreshConfiguration()

            XCTAssertEqual(controller.statusItem.button?.accessibilityLabel(), "Start project")
        }
    }

    @MainActor
    func testStartingProjectLaunchesOnlySelectedConfiguration() {
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
        var receivedPlans: [XcodeProjectLaunchPlan] = []
        catalog.selectLaunchConfiguration(scheme: "Example-iOS", forProjectAt: 0)
        let controller = StatusBarController(
            projectCatalog: catalog,
            appSettings: settings,
            cacheDirectory: URL(fileURLWithPath: "/Caches/XPlay"),
            makeLauncher: { plan in
                receivedPlans.append(plan)
                return DeferredProjectLauncher()
            }
        )

        controller.perform(.startProject)

        XCTAssertEqual(receivedPlans.map(\.scheme), ["Example-iOS"])
        XCTAssertTrue(receivedPlans.allSatisfy(\.acceptsMacros))
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
            catalog.selectLaunchConfiguration(scheme: "Example-iOS", forProjectAt: 0)
            let launcher = DeferredProjectLauncher()
            let controller = StatusBarController(
                projectCatalog: catalog,
                appSettings: settings,
                makeLauncher: { _ in launcher }
            )

            controller.perform(.startProject)

            XCTAssertEqual(
                controller.statusItem.button?.accessibilityLabel(),
                "Starting Example-iOS"
            )
            XCTAssertEqual(
                controller.statusItem.button?.toolTip,
                "Building and launching Example-iOS…"
            )
        }
    }

    @MainActor
    func testRunningStatusShowsThreeAnimatedDotsBesideIconInsteadOfSpinner() throws {
        try withState { catalog, settings in
            let mac = XcodeDestination(platform: .macOS, id: "mac", name: "My Mac")
            configure(catalog, schemes: ["Example"], destinations: [[mac]])
            let controller = StatusBarController(
                projectCatalog: catalog,
                appSettings: settings,
                makeLauncher: { _ in DeferredProjectLauncher() }
            )

            controller.perform(.startProject)

            let button = try XCTUnwrap(controller.statusItem.button)
            let views = descendants(of: button)
            let runningIndicator = try XCTUnwrap(
                views.first { $0.identifier?.rawValue == "running-indicator" }
            )
            let runningIcon = try XCTUnwrap(
                views.compactMap { $0 as? NSImageView }.first {
                    $0.identifier?.rawValue == "running-status-icon"
                }
            )
            let dots = views.filter {
                $0.identifier?.rawValue.hasPrefix("running-dot-") == true
            }

            XCTAssertFalse(runningIndicator.isHidden)
            XCTAssertNotNil(runningIcon.image)
            XCTAssertEqual(dots.count, 3)
            XCTAssertTrue(dots.allSatisfy { $0.layer?.animation(forKey: "pulse") != nil })
            XCTAssertTrue(views.compactMap { $0 as? NSProgressIndicator }.isEmpty)
            XCTAssertNotEqual(controller.statusItem.length, NSStatusItem.squareLength)
            XCTAssertNil(button.image)
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

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(descendants(of:))
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
