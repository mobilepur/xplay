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
    func testWindowUsesProjectManagementLayout() throws {
        try withCatalog { catalog in
            catalog.add(URL(fileURLWithPath: "/Projects/Example.xcodeproj"))
            let controller = ProjectWindowController(catalog: catalog)

            controller.loadWindow()

            XCTAssertEqual(controller.window?.title, "XPlay Projects")
            XCTAssertEqual(controller.tableView.numberOfRows, 1)
            XCTAssertEqual(controller.addButton.title, "Add Project…")

            let contentView = try XCTUnwrap(controller.window?.contentView)
            XCTAssertTrue(
                descendants(of: NSTextField.self, in: contentView)
                    .contains { $0.stringValue == "Projects" }
            )
            XCTAssertTrue(
                descendants(of: NSButton.self, in: contentView)
                    .contains { $0.title == "Done" }
            )

            let cell = try XCTUnwrap(
                controller.tableView(
                    controller.tableView,
                    viewFor: controller.tableView.tableColumns[0],
                    row: 0
                )
            )
            XCTAssertEqual(
                descendants(of: NSTextField.self, in: cell).map(\.stringValue),
                ["Example", "/Projects/Example.xcodeproj"]
            )
            XCTAssertTrue(
                descendants(of: NSButton.self, in: cell)
                    .contains { $0.toolTip == "Remove Example" }
            )

            let panel = controller.makeProjectOpenPanel()
            XCTAssertTrue(panel.canChooseFiles)
            XCTAssertFalse(panel.canChooseDirectories)
            XCTAssertFalse(panel.allowsMultipleSelection)
            XCTAssertEqual(panel.allowedContentTypes.first?.preferredFilenameExtension, "xcodeproj")
        }
    }

    @MainActor
    func testAddingAndRemovingProjectRefreshesWindow() throws {
        try withCatalog { catalog in
            let controller = ProjectWindowController(catalog: catalog)
            controller.loadWindow()

            controller.addProject(at: URL(fileURLWithPath: "/Projects/Example.xcodeproj"))

            XCTAssertEqual(controller.tableView.numberOfRows, 1)
            let cell = try XCTUnwrap(
                controller.tableView(
                    controller.tableView,
                    viewFor: controller.tableView.tableColumns[0],
                    row: 0
                )
            )
            let removeButton = try XCTUnwrap(
                descendants(of: NSButton.self, in: cell)
                    .first { $0.toolTip == "Remove Example" }
            )

            removeButton.performClick(nil)

            XCTAssertEqual(controller.tableView.numberOfRows, 0)
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
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        try body(ProjectCatalog(defaults: defaults, storageKey: "projects"))
    }

    @MainActor
    private func descendants<View: NSView>(of type: View.Type, in root: NSView) -> [View] {
        let current = (root as? View).map { [$0] } ?? []
        return current + root.subviews.flatMap { descendants(of: type, in: $0) }
    }
}
