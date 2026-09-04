import AppKit
import Foundation
import XCTest
@testable import XPlay

final class ProjectWindowControllerTests: XCTestCase {
    @MainActor
    func testShowingProjectsLoadsAndDisplaysWindow() {
        withCatalog { catalog in
            let controller = ProjectWindowController(catalog: catalog)

            controller.showProjects()
            defer { controller.close() }

            XCTAssertNotNil(controller.window)
            XCTAssertEqual(controller.window?.isVisible, true)
        }
    }

    @MainActor
    func testWindowUsesWorkspaceAndSchemeConfigurationLayout() throws {
        try withCatalog { catalog in
            catalog.add(URL(fileURLWithPath: "/Projects/Example.xcworkspace"))
            let controller = ProjectWindowController(catalog: catalog)

            controller.loadWindow()

            XCTAssertEqual(controller.window?.title, "XPlay Projects")
            XCTAssertEqual(controller.projectTableView.numberOfRows, 1)
            XCTAssertEqual(controller.schemeTableView.numberOfRows, 0)
            XCTAssertEqual(controller.addButton.title, "Add Workspace…")

            let contentView = try XCTUnwrap(controller.window?.contentView)
            XCTAssertTrue(
                descendants(of: NSTextField.self, in: contentView)
                    .contains { $0.stringValue == "Schemes" }
            )
            XCTAssertFalse(
                descendants(of: NSButton.self, in: contentView)
                    .contains { $0.title == "Accept Macros" }
            )

            let projectCell = try XCTUnwrap(
                controller.tableView(
                    controller.projectTableView,
                    viewFor: controller.projectTableView.tableColumns[0],
                    row: 0
                )
            )
            XCTAssertEqual(
                descendants(of: NSTextField.self, in: projectCell).map(\.stringValue),
                ["Example", "/Projects/Example.xcworkspace"]
            )

            let panel = controller.makeWorkspaceOpenPanel()
            XCTAssertTrue(panel.canChooseFiles)
            XCTAssertFalse(panel.canChooseDirectories)
            XCTAssertFalse(panel.allowsMultipleSelection)
            XCTAssertEqual(panel.allowedContentTypes.first?.preferredFilenameExtension, "xcworkspace")
        }
    }

    @MainActor
    func testAddingWorkspaceDiscoversCheckmarkedSchemesAndDestination() async throws {
        try await withCatalog { catalog in
            let controller = ProjectWindowController(
                catalog: catalog,
                schemeResolver: makeResolver(
                    schemes: ["Example-macOS", "Example-iOS"],
                    destinations: """
                        { platform:macOS, arch:arm64, id:mac-id, name:My Mac }
                    """
                )
            )
            controller.loadWindow()

            await controller.addWorkspace(
                at: URL(fileURLWithPath: "/Projects/Example.xcworkspace")
            )

            XCTAssertEqual(controller.projectTableView.numberOfRows, 1)
            XCTAssertEqual(controller.schemeTableView.numberOfRows, 2)
            let schemeCell = try XCTUnwrap(
                controller.tableView(
                    controller.schemeTableView,
                    viewFor: controller.schemeTableView.tableColumns[0],
                    row: 0
                )
            )
            let checkbox = try XCTUnwrap(
                descendants(of: NSButton.self, in: schemeCell)
                    .first { $0.title == "Example-macOS" }
            )
            XCTAssertEqual(checkbox.state, .off)

            await controller.setSchemeEnabled(true, scheme: "Example-macOS")

            XCTAssertTrue(catalog.selectedProject?.configurations[0].isEnabled == true)
            XCTAssertEqual(
                catalog.selectedProject?.configurations[0].selectedDestination?.name,
                "My Mac"
            )
        }
    }

    @MainActor
    func testChoosingDestinationMakesSchemeActiveForPlay() throws {
        try withCatalog { catalog in
            let workspaceURL = URL(fileURLWithPath: "/Projects/Example.xcworkspace")
            let mac = XcodeDestination(platform: .macOS, id: "mac", name: "My Mac")
            let simulator = XcodeDestination(
                platform: .iOSSimulator,
                id: "sim",
                name: "iPhone 17 Pro"
            )
            catalog.add(workspaceURL, schemes: ["Example-macOS", "Example-iOS"])
            catalog.setSchemeEnabled(true, scheme: "Example-macOS", forProjectAt: 0)
            catalog.updateDestinations([mac], scheme: "Example-macOS", forProjectAt: 0)
            catalog.setSchemeEnabled(true, scheme: "Example-iOS", forProjectAt: 0)
            catalog.updateDestinations([simulator], scheme: "Example-iOS", forProjectAt: 0)
            let controller = ProjectWindowController(catalog: catalog)
            controller.loadWindow()
            let iosCell = try XCTUnwrap(
                controller.tableView(
                    controller.schemeTableView,
                    viewFor: controller.schemeTableView.tableColumns[0],
                    row: 1
                )
            )
            let selector = try XCTUnwrap(
                descendants(of: NSPopUpButton.self, in: iosCell).first
            )
            let action = try XCTUnwrap(selector.action)

            XCTAssertTrue(
                NSApp.sendAction(action, to: selector.target, from: selector)
            )

            XCTAssertEqual(
                catalog.selectedProject?.selectedLaunchConfiguration?.scheme,
                "Example-iOS"
            )
        }
    }

    @MainActor
    func testRemovingWorkspaceRefreshesBothTables() async throws {
        try await withCatalog { catalog in
            let controller = ProjectWindowController(
                catalog: catalog,
                schemeResolver: makeResolver(schemes: ["Example"], destinations: "")
            )
            controller.loadWindow()
            await controller.addWorkspace(
                at: URL(fileURLWithPath: "/Projects/Example.xcworkspace")
            )

            let projectCell = try XCTUnwrap(
                controller.tableView(
                    controller.projectTableView,
                    viewFor: controller.projectTableView.tableColumns[0],
                    row: 0
                )
            )
            let removeButton = try XCTUnwrap(
                descendants(of: NSButton.self, in: projectCell)
                    .first { $0.toolTip == "Remove Example" }
            )

            removeButton.performClick(nil)

            XCTAssertEqual(controller.projectTableView.numberOfRows, 0)
            XCTAssertEqual(controller.schemeTableView.numberOfRows, 0)
        }
    }

    @MainActor
    func testRefreshPreservesEnabledMatchingScheme() async {
        await withCatalog { catalog in
            catalog.add(
                URL(fileURLWithPath: "/Projects/Example.xcworkspace"),
                schemes: ["Old", "Selected"]
            )
            catalog.setSchemeEnabled(true, scheme: "Selected", forProjectAt: 0)
            let controller = ProjectWindowController(
                catalog: catalog,
                schemeResolver: makeResolver(
                    schemes: ["Selected", "New"],
                    destinations: "{ platform:macOS, id:mac-id, name:My Mac }"
                )
            )
            controller.loadWindow()

            await controller.refreshSchemes()

            XCTAssertEqual(catalog.projects[0].schemes, ["Selected", "New"])
            XCTAssertEqual(catalog.selectedProject?.enabledConfigurations.map(\.scheme), ["Selected"])
        }
    }

    @MainActor
    func testSchemeLoadingRetainsCachedRowsAndShowsAccessibleStatus() async {
        await withCatalog { catalog in
            catalog.add(
                URL(fileURLWithPath: "/Projects/Example.xcworkspace"),
                schemes: ["CachedScheme"]
            )
            let resolutionStarted = expectation(description: "Scheme resolution started")
            let allowResolutionToFinish = DispatchSemaphore(value: 0)
            let resolver = XcodeSchemeResolver { _ in
                resolutionStarted.fulfill()
                allowResolutionToFinish.wait()
                return Data("{\"workspace\":{\"schemes\":[\"CachedScheme\"]}}".utf8)
            }
            let controller = ProjectWindowController(catalog: catalog, schemeResolver: resolver)
            controller.loadWindow()

            let refresh = Task { await controller.refreshSchemes() }
            await fulfillment(of: [resolutionStarted], timeout: 2)

            XCTAssertEqual(controller.schemeTableView.numberOfRows, 1)
            XCTAssertEqual(controller.schemeStatusLabel.stringValue, "Loading schemes…")
            XCTAssertEqual(controller.schemeStatusLabel.accessibilityLabel(), "Loading schemes")

            allowResolutionToFinish.signal()
            await refresh.value
        }
    }

    @MainActor
    func testSelectingProjectDuringSchemeResolutionUpdatesLoadingStatus() async throws {
        try await withCatalog { catalog in
            let firstURL = URL(fileURLWithPath: "/Projects/First.xcworkspace")
            let secondURL = URL(fileURLWithPath: "/Projects/Second.xcworkspace")
            catalog.add(firstURL, schemes: ["FirstCached"])
            catalog.add(secondURL, schemes: ["SecondCached"])
            catalog.selectProject(at: 0)
            let secondResolutionStarted = expectation(description: "Second resolution started")
            let allowSecondResolutionToFinish = DispatchSemaphore(value: 0)
            let resolver = XcodeSchemeResolver { arguments in
                if arguments.contains(secondURL.path) {
                    secondResolutionStarted.fulfill()
                    allowSecondResolutionToFinish.wait()
                    return Data("{\"workspace\":{\"schemes\":[\"SecondCached\"]}}".utf8)
                }
                return Data("{\"workspace\":{\"schemes\":[\"FirstCached\"]}}".utf8)
            }
            let controller = ProjectWindowController(catalog: catalog, schemeResolver: resolver)
            controller.loadWindow()
            let refresh = Task { await controller.refreshSchemes() }
            await fulfillment(of: [secondResolutionStarted], timeout: 2)

            controller.projectTableView.selectRowIndexes(
                IndexSet(integer: 1),
                byExtendingSelection: false
            )
            controller.tableViewSelectionDidChange(
                Notification(name: NSTableView.selectionDidChangeNotification,
                             object: controller.projectTableView)
            )

            XCTAssertEqual(controller.schemeTableView.numberOfRows, 1)
            let cell = try XCTUnwrap(
                controller.tableView(
                    controller.schemeTableView,
                    viewFor: controller.schemeTableView.tableColumns[0],
                    row: 0
                )
            )
            XCTAssertTrue(descendants(of: NSButton.self, in: cell).contains {
                $0.title == "SecondCached"
            })
            XCTAssertEqual(controller.schemeStatusLabel.stringValue, "Loading schemes…")
            XCTAssertEqual(controller.schemeStatusLabel.accessibilityLabel(), "Loading schemes")

            allowSecondResolutionToFinish.signal()
            await refresh.value
        }
    }

    @MainActor
    func testDestinationLoadingRetainsCurrentSelection() async throws {
        try await withCatalog { catalog in
            let mac = XcodeDestination(platform: .macOS, id: "mac", name: "My Mac")
            catalog.add(
                URL(fileURLWithPath: "/Projects/Example.xcworkspace"),
                schemes: ["Example"]
            )
            catalog.setSchemeEnabled(true, scheme: "Example", forProjectAt: 0)
            catalog.updateDestinations([mac], scheme: "Example", forProjectAt: 0)
            let resolutionStarted = expectation(description: "Destination resolution started")
            let allowResolutionToFinish = DispatchSemaphore(value: 0)
            let resolver = XcodeSchemeResolver { arguments in
                guard arguments.first == "-showdestinations" else {
                    return Data("{\"workspace\":{\"schemes\":[\"Example\"]}}".utf8)
                }
                resolutionStarted.fulfill()
                allowResolutionToFinish.wait()
                return Data("{ platform:macOS, id:mac, name:My Mac }".utf8)
            }
            let controller = ProjectWindowController(catalog: catalog, schemeResolver: resolver)
            controller.loadWindow()

            let refresh = Task { await controller.setSchemeEnabled(true, scheme: "Example") }
            await fulfillment(of: [resolutionStarted], timeout: 2)
            let cell = try XCTUnwrap(
                controller.tableView(
                    controller.schemeTableView,
                    viewFor: controller.schemeTableView.tableColumns[0],
                    row: 0
                )
            )
            let selector = try XCTUnwrap(descendants(of: NSPopUpButton.self, in: cell).first)

            XCTAssertEqual(selector.titleOfSelectedItem, "My Mac")
            XCTAssertTrue(selector.itemTitles.contains("Loading destinations…"))

            allowResolutionToFinish.signal()
            await refresh.value
        }
    }

    @MainActor
    func testSchemeResolutionFailureCanRetryAffectedWorkspace() async {
        await withCatalog { catalog in
            catalog.add(URL(fileURLWithPath: "/Projects/Example.xcworkspace"))
            let attempts = AttemptBox()
            let resolver = XcodeSchemeResolver { _ in
                if attempts.incrementAndGet() == 1 {
                    throw TestResolutionError.failed
                }
                return Data("{\"workspace\":{\"schemes\":[\"Example\"]}}".utf8)
            }
            var failures: [ProjectWindowController.ResolutionFailure] = []
            let controller = ProjectWindowController(
                catalog: catalog,
                schemeResolver: resolver,
                presentResolutionFailure: { failure in
                    failures.append(failure)
                    return true
                }
            )
            controller.loadWindow()

            await controller.refreshSchemes()

            XCTAssertEqual(attempts.value, 2)
            XCTAssertEqual(failures.map(\.projectName), ["Example"])
            XCTAssertEqual(failures.map(\.subject), ["schemes"])
            XCTAssertEqual(catalog.selectedProject?.schemes, ["Example"])
        }
    }

    @MainActor
    func testDoneClosesProjectWindow() throws {
        try withCatalog { catalog in
            let controller = ProjectWindowController(catalog: catalog)
            controller.showProjects()
            defer { controller.close() }

            let contentView = try XCTUnwrap(controller.window?.contentView)
            let doneButton = try XCTUnwrap(
                descendants(of: NSButton.self, in: contentView)
                    .first { $0.title == "Done" }
            )

            doneButton.performClick(nil)

            XCTAssertEqual(controller.window?.isVisible, false)
        }
    }

    @MainActor
    private func withCatalog(_ body: (ProjectCatalog) throws -> Void) rethrows {
        let suiteName = "ProjectWindowControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(ProjectCatalog(defaults: defaults, storageKey: "projects"))
    }

    @MainActor
    private func withCatalog(
        _ body: (ProjectCatalog) async throws -> Void
    ) async rethrows {
        let suiteName = "ProjectWindowControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try await body(ProjectCatalog(defaults: defaults, storageKey: "projects"))
    }

    private func makeResolver(schemes: [String], destinations: String) -> XcodeSchemeResolver {
        XcodeSchemeResolver { arguments in
            if arguments.first == "-showdestinations" {
                return Data(destinations.utf8)
            }
            let encodedSchemes = try JSONEncoder().encode(schemes)
            let encodedString = String(decoding: encodedSchemes, as: UTF8.self)
            return Data("{\"workspace\":{\"schemes\":\(encodedString)}}".utf8)
        }
    }

    @MainActor
    private func descendants<View: NSView>(of type: View.Type, in root: NSView) -> [View] {
        let current = (root as? View).map { [$0] } ?? []
        return current + root.subviews.flatMap { descendants(of: type, in: $0) }
    }
}

private enum TestResolutionError: Error {
    case failed
}

private final class AttemptBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        lock.withLock { storage }
    }

    func incrementAndGet() -> Int {
        lock.withLock {
            storage += 1
            return storage
        }
    }
}
