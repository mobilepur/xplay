import AppKit
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
    func testContextMenuShowsProjectsSectionAndQuitAction() throws {
        let controller = StatusBarController()
        let items = controller.contextMenu.items

        XCTAssertEqual(
            items.map(\.title),
            ["No project selected", "", "Projects", "No projects yet", "", "Quit"]
        )
        guard items.count == 6 else {
            return
        }

        let headerView = try XCTUnwrap(items[2].view)
        let titleLabel = try XCTUnwrap(headerView.subviews.compactMap { $0 as? NSTextField }.first)
        let editButton = try XCTUnwrap(headerView.subviews.compactMap { $0 as? NSButton }.first)

        XCTAssertEqual(titleLabel.stringValue, "Projects")
        XCTAssertEqual(editButton.title, "Edit")
        XCTAssertFalse(editButton.isEnabled)
        XCTAssertFalse(items[0].isEnabled)
        XCTAssertFalse(items[3].isEnabled)
        XCTAssertTrue(items[5].isEnabled)
        XCTAssertEqual(items[5].keyEquivalent, "q")
    }
}
