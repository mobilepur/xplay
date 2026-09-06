import AppKit
import XCTest
@testable import XPlay

@MainActor
final class WorkingCopyMenuTests: XCTestCase {
    func testBranchRowsShowOnlyNameWithNativeWorktreeSubtitle() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let newCopy = GitWorkingCopy(id: "new", branchName: "feature/new", head: "abc1234",
            rootURL: nil, containerURL: nil, lastActivity: .now, isDirty: false, isMainWorktree: false)
        let controller = StatusBarController(projectCatalog: fixture.catalog,
            appSettings: AppSettings(defaults: fixture.defaults),
            workingCopyResolver: MenuTestResolver(state: GitRepositoryState(
                rootURL: fixture.directory, workingCopies: [fixture.copies[4], fixture.copies[0], newCopy])))
        await controller.refreshWorkingCopies()
        let rows = controller.contextMenu.items.filter { $0.identifier?.rawValue == "working-copy" }
        XCTAssertEqual(rows.map(\.title), ["main", "feature-0", "feature/new"])
        XCTAssertEqual(rows.map(\.subtitle), [nil, "Worktree", "New Worktree"])
        let schemeRow = try XCTUnwrap(controller.contextMenu.items.compactMap(\.view).first {
            $0.subviews.contains { $0.identifier?.rawValue == "scheme-selection-button" }
        })
        schemeRow.layoutSubtreeIfNeeded()
        let schemeLabel = try XCTUnwrap(schemeRow.subviews.compactMap { $0 as? NSTextField }.first {
            $0.stringValue == "Example"
        })
        let schemeCheckmark = try XCTUnwrap(schemeRow.subviews.compactMap { $0 as? NSImageView }.first {
            $0.identifier?.rawValue == "configuration-checkmark"
        })
        XCTAssertEqual(schemeCheckmark.contentTintColor, .systemBlue)
        let projectItem = try XCTUnwrap(controller.contextMenu.items.first { $0.title == fixture.catalog.selectedProject?.name && $0.action != nil })
        for item in rows + [projectItem] {
            let row = try XCTUnwrap(item.view)
            let button = try XCTUnwrap(row.subviews.compactMap { $0 as? NSButton }.first)
            let label = try XCTUnwrap(row.subviews.compactMap { $0 as? NSTextField }.first {
                $0.identifier?.rawValue == "selection-title"
            })
            let checkbox = try XCTUnwrap(row.subviews.compactMap { $0 as? NSImageView }.first {
                $0.identifier?.rawValue == "configuration-checkmark"
            })
            XCTAssertFalse(checkbox.isHidden, "Unselected rows keep an empty circle in the same column")
            if item.state == .on {
                XCTAssertEqual(checkbox.contentTintColor, .systemBlue)
            }
            for width in [row.frame.width, CGFloat(600)] {
                row.frame.size.width = width
                row.layoutSubtreeIfNeeded()
                XCTAssertEqual(label.frame.minX, schemeLabel.frame.minX, accuracy: 0.5)
                XCTAssertEqual(checkbox.frame.minX, schemeCheckmark.frame.minX, accuracy: 0.5)
                XCTAssertEqual(checkbox.frame.size, schemeCheckmark.frame.size)
                XCTAssertTrue(row.hitTest(NSPoint(x: width - 1, y: row.bounds.midY)) === button,
                              "The entire row remains selectable, including its right edge")
            }
        }
        XCTAssertEqual(rows[0].state, .on)
        XCTAssertTrue(rows[1].toolTip?.contains("Modified") == true)
        XCTAssertTrue(rows.allSatisfy { $0.view?.subviews.contains(where: { $0 is NSButton }) == true }, "Branch selection uses an embedded button to keep the menu open")
    }

    func testThreeRecentBranchesAndOverflowKeepOlderCurrentBranchVisible() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let controller = fixture.controller()
        await controller.refreshWorkingCopies()
        let menu = controller.contextMenu
        let recent = menu.items.filter { $0.identifier?.rawValue == "working-copy" }
        XCTAssertEqual(recent.map { $0.representedObject as? String }, ["feature-0", "feature-1", "feature-2"])
        XCTAssertNil(menu.items.first { $0.title == "Show More…" })
        let header = try XCTUnwrap(menu.items.first { $0.title == "Recent Branches" })
        let button = try XCTUnwrap(header.view?.subviews.compactMap { $0 as? NSButton }.first)
        XCTAssertEqual(button.title, "Show More…")
        header.view?.layoutSubtreeIfNeeded()
        let label = try XCTUnwrap(header.view?.subviews.compactMap { $0 as? NSTextField }.first)
        XCTAssertGreaterThan(button.frame.minX, label.frame.maxX)
        XCTAssertNil(header.submenu)
        button.performClick(nil)
        let overflow = try XCTUnwrap(header.submenu)
        XCTAssertTrue(overflow.supermenu === menu)
        XCTAssertEqual(overflow.items.map { $0.representedObject as? String }, ["feature-3", "main"])
        XCTAssertEqual(overflow.items.last?.state, .on)
        overflow.delegate?.menuDidClose?(overflow)
        XCTAssertNil(header.submenu)
        let current = try XCTUnwrap(menu.items.first { $0.identifier?.rawValue == "current-branch" })
        XCTAssertEqual(current.title, "Branch: main")
        XCTAssertEqual(current.toolTip, fixture.anchor.path)
        XCTAssertEqual(menu.index(of: current) + 1, menu.index(of: menu.items.first { $0.title == "Run Project" }!))
    }

    func testSelectingOverflowWorktreeRoutesRunOpenAndDiscoveryToSameContainer() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var opened: [URL] = []
        var plans: [XcodeProjectLaunchPlan] = []
        let discovery = URLRecorder()
        let controller = fixture.controller(
            schemeResolver: XcodeSchemeResolver { arguments in
                if let index = arguments.firstIndex(of: "-workspace") {
                    discovery.append(URL(fileURLWithPath: arguments[index + 1]))
                }
                return Data("{ platform:macOS, id:mac, name:My Mac }".utf8)
            },
            makeLauncher: { plan in plans.append(plan); return MenuTestLauncher() },
            open: { opened.append($0) }
        )
        await controller.refreshWorkingCopies()
        let header = try XCTUnwrap(controller.contextMenu.items.first { $0.title == "Recent Branches" })
        let button = try XCTUnwrap(header.view?.subviews.compactMap { $0 as? NSButton }.first)
        button.performClick(nil)
        let overflow = try XCTUnwrap(header.submenu)
        let branchButton = try XCTUnwrap(overflow.items[0].view?.subviews.compactMap { $0 as? NSButton }.first)
        branchButton.performClick(nil)
        let selected = expectation(for: NSPredicate { _, _ in
            MainActor.assumeIsolated {
                fixture.catalog.selectedProject?.activeContainerURL.path == fixture.copies[3].containerURL?.path
            }
        }, evaluatedWith: nil)
        await fulfillment(of: [selected], timeout: 3)
        // Wait for the selected working copy's destination refresh, not a timer delay.
        let ready = expectation(for: NSPredicate { _, _ in
            MainActor.assumeIsolated {
                let row = controller.contextMenu.items.first { $0.title == "Run Project" }?.view
                return row?.subviews.compactMap { $0 as? NSButton }.first {
                    $0.identifier?.rawValue == "run-project-button"
                }?.isEnabled == true
            }
        }, evaluatedWith: nil)
        await fulfillment(of: [ready], timeout: 3)
        await controller.openSelectedProject()
        controller.perform(.startProject)
        let target = try XCTUnwrap(fixture.copies[3].containerURL)
        XCTAssertEqual(opened.map(\.path), [target.path])
        XCTAssertEqual(plans.map { $0.containerURL.path }, [target.path])
        XCTAssertEqual(discovery.values.map(\.path), [target.path])
        XCTAssertEqual(fixture.catalog.selectedProject?.url.path, fixture.anchor.path)
        XCTAssertEqual(controller.contextMenu.items.first { $0.identifier?.rawValue == "current-branch" }?.title,
                       "Branch: feature-3")
        XCTAssertTrue(header.submenu === overflow, "Selection keeps the submenu attached")
        XCTAssertEqual(overflow.items[0].state, .on)
        controller.menuDidClose(controller.contextMenu)
        controller.perform(.startProject) // Stop the test launcher.
    }

    func testNoGitProjectStillOpensAndHasNoOverflow() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var opened: [URL] = []
        let controller = StatusBarController(projectCatalog: fixture.catalog,
            workingCopyResolver: MenuTestResolver(state: nil),
            openProjectInXcode: { opened.append($0) })
        await controller.refreshWorkingCopies()
        XCTAssertNil(controller.contextMenu.items.first { $0.title == "Show More…" })
        XCTAssertEqual(controller.contextMenu.items.first { $0.identifier?.rawValue == "current-branch" }?.title,
                       "Local project · No Git repository")
        await controller.openSelectedProject()
        XCTAssertEqual(opened.map(\.path), [fixture.anchor.path])
    }

    func testRemovedSelectedWorktreeNeverFallsBackToMainForRunOrOpen() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var opened: [URL] = []
        var plans: [XcodeProjectLaunchPlan] = []
        let controller = fixture.controller(makeLauncher: { plans.append($0); return MenuTestLauncher() },
                                            open: { opened.append($0) })
        await controller.refreshWorkingCopies()
        await controller.selectWorkingCopy(id: "feature-0")
        let target = try XCTUnwrap(fixture.copies[0].containerURL)
        try FileManager.default.removeItem(at: target)
        controller.refreshConfiguration()
        await controller.openSelectedProject()
        controller.perform(.startProject)
        XCTAssertTrue(opened.isEmpty)
        XCTAssertTrue(plans.isEmpty)
        XCTAssertEqual(fixture.catalog.selectedProject?.activeContainerURL.path, target.path)
    }

    func testFailedRefreshRemainsVisibleWithCachedBranchesAndRecovers() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let resolver = RecoveringMenuResolver(state: GitRepositoryState(
            rootURL: fixture.anchor.deletingLastPathComponent(), workingCopies: fixture.copies))
        let controller = StatusBarController(projectCatalog: fixture.catalog,
            workingCopyResolver: resolver)
        await controller.refreshWorkingCopies()
        resolver.setFailure(true)
        await controller.refreshWorkingCopies()
        XCTAssertNotNil(controller.contextMenu.items.first {
            $0.title == "Could not read branches. Reopen menu to retry."
        })
        XCTAssertEqual(controller.contextMenu.items.first {
            $0.identifier?.rawValue == "current-branch"
        }?.title, "Branch unavailable")
        resolver.setFailure(false)
        await controller.refreshWorkingCopies()
        XCTAssertNil(controller.contextMenu.items.first {
            $0.title == "Could not read branches. Reopen menu to retry."
        })
        XCTAssertEqual(controller.contextMenu.items.first {
            $0.identifier?.rawValue == "current-branch"
        }?.title, "Branch: main")
    }

    func testAutomaticSelectionDefaultsOffAndUsesNewestBranchWhenEnabled() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let manual = fixture.controller()
        await manual.refreshWorkingCopies()
        XCTAssertEqual(fixture.catalog.selectedProject?.activeContainerURL.path, fixture.anchor.path)
        fixture.defaults.set(true, forKey: "settings.automaticallySelectLatestBranch")
        let automatic = fixture.controller()
        await automatic.refreshWorkingCopies()
        XCTAssertEqual(fixture.catalog.selectedProject?.activeContainerURL.path, fixture.copies[0].containerURL?.path)
    }

    func testAutomaticSelectionTogglePersistsAndDisablingKeepsManualChoice() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let controller = fixture.controller()
        await controller.refreshWorkingCopies()
        let item = try XCTUnwrap(controller.contextMenu.items.first {
            $0.title == "Automatically Select Latest Branch"
        })
        let toggle = try XCTUnwrap(item.view?.subviews.compactMap { $0 as? NSSwitch }.first)
        XCTAssertEqual(toggle.state, .off)
        toggle.state = .on
        toggle.sendAction(toggle.action, to: toggle.target)
        let selected = expectation(for: NSPredicate { _, _ in MainActor.assumeIsolated {
            fixture.catalog.selectedProject?.activeContainerURL.path == fixture.copies[0].containerURL?.path
        } }, evaluatedWith: nil)
        await fulfillment(of: [selected], timeout: 3)
        XCTAssertTrue(fixture.defaults.bool(forKey: "settings.automaticallySelectLatestBranch"))
        let reloaded = fixture.controller()
        let persisted = try XCTUnwrap(reloaded.contextMenu.items.first {
            $0.title == "Automatically Select Latest Branch"
        }?.view?.subviews.compactMap { $0 as? NSSwitch }.first)
        XCTAssertEqual(persisted.state, .on)
        toggle.state = .off
        toggle.sendAction(toggle.action, to: toggle.target)
        await controller.selectWorkingCopy(id: "feature-3")
        await controller.refreshWorkingCopies()
        XCTAssertFalse(fixture.defaults.bool(forKey: "settings.automaticallySelectLatestBranch"))
        XCTAssertEqual(fixture.catalog.selectedProject?.activeContainerURL.path, fixture.copies[3].containerURL?.path)
    }

    func testAutomaticRunAndOpenRefreshSelectionBeforeUsingContainer() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        fixture.defaults.set(true, forKey: "settings.automaticallySelectLatestBranch")
        var plans: [XcodeProjectLaunchPlan] = []
        let run = fixture.controller(makeLauncher: { plans.append($0); return MenuTestLauncher() })
        run.perform(.startProject)
        let launched = expectation(for: NSPredicate { _, _ in MainActor.assumeIsolated {
            !plans.isEmpty
        } }, evaluatedWith: nil)
        await fulfillment(of: [launched], timeout: 3)
        XCTAssertEqual(plans.first?.containerURL.path, fixture.copies[0].containerURL?.path)
        run.perform(.startProject)
        fixture.catalog.selectWorkingCopy(containerURL: nil, forProjectAt: 0)
        var opened: [URL] = []
        let open = fixture.controller(open: { opened.append($0) })
        await open.openSelectedProject()
        XCTAssertEqual(opened.first?.path, fixture.copies[0].containerURL?.path)
    }

    func testAutomaticSelectionDoesNotSwitchWhileRunning() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var plans: [XcodeProjectLaunchPlan] = []
        let controller = fixture.controller(makeLauncher: { plans.append($0); return MenuTestLauncher() })
        controller.perform(.startProject)
        let toggle = try XCTUnwrap(controller.contextMenu.items.first {
            $0.title == "Automatically Select Latest Branch"
        }?.view?.subviews.compactMap { $0 as? NSSwitch }.first)
        toggle.state = .on
        toggle.sendAction(toggle.action, to: toggle.target)
        await controller.refreshWorkingCopies(force: true)
        XCTAssertEqual(plans.map { $0.containerURL.path }, [fixture.anchor.path])
        XCTAssertEqual(fixture.catalog.selectedProject?.activeContainerURL.path, fixture.anchor.path)
        controller.perform(.startProject)
    }

    func testAutomaticOpenDoesNotFallBackWhenGitRefreshFails() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        fixture.defaults.set(true, forKey: "settings.automaticallySelectLatestBranch")
        let resolver = RecoveringMenuResolver(state: GitRepositoryState(
            rootURL: fixture.anchor.deletingLastPathComponent(), workingCopies: fixture.copies))
        resolver.setFailure(true)
        var opened: [URL] = []
        let controller = StatusBarController(projectCatalog: fixture.catalog,
            appSettings: AppSettings(defaults: fixture.defaults), workingCopyResolver: resolver,
            openProjectInXcode: { opened.append($0) })
        await controller.openSelectedProject()
        XCTAssertTrue(opened.isEmpty)
        XCTAssertEqual(controller.contextMenu.items.first {
            $0.identifier?.rawValue == "current-branch"
        }?.title, "Branch unavailable")
    }

    @MainActor
    private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "WorkingCopyMenuTests.\(UUID().uuidString)"
        let defaults: UserDefaults
        let catalog: ProjectCatalog
        let anchor: URL
        let copies: [GitWorkingCopy]

        init() throws {
            defaults = UserDefaults(suiteName: suite)!
            catalog = ProjectCatalog(defaults: defaults)
            anchor = directory.appendingPathComponent("main/Example.xcworkspace")
            let names = ["feature-0", "feature-1", "feature-2", "feature-3", "main"]
            let fixtureDirectory = directory
            copies = try names.enumerated().map { index, name in
                let root = fixtureDirectory.appendingPathComponent(name)
                let container = root.appendingPathComponent("Example.xcworkspace")
                try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
                return GitWorkingCopy(id: name, branchName: name, head: "abc1234", rootURL: root,
                    containerURL: container, lastActivity: Date(timeIntervalSince1970: Double(100 - index)),
                    isDirty: index == 0, isMainWorktree: name == "main")
            }
            catalog.add(anchor, schemes: ["Example"])
            catalog.setSchemeEnabled(true, scheme: "Example", forProjectAt: 0)
            catalog.updateDestinations([XcodeDestination(platform: .macOS, id: "mac", name: "My Mac")],
                                       scheme: "Example", forProjectAt: 0)
        }

        func controller(
            schemeResolver: XcodeSchemeResolver = XcodeSchemeResolver { _ in
                Data("{ platform:macOS, id:mac, name:My Mac }".utf8)
            },
            makeLauncher: @escaping (XcodeProjectLaunchPlan) -> any ProjectLaunching = { _ in MenuTestLauncher() },
            open: @escaping @MainActor (URL) async throws -> Void = { _ in }
        ) -> StatusBarController {
            StatusBarController(projectCatalog: catalog, appSettings: AppSettings(defaults: defaults),
                schemeResolver: schemeResolver, makeLauncher: makeLauncher,
                openDestinationSubmenu: { _ in },
                workingCopyResolver: MenuTestResolver(state: GitRepositoryState(
                    rootURL: anchor.deletingLastPathComponent(), workingCopies: copies)),
                openProjectInXcode: open)
        }

        func remove() {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
    }
}

private struct MenuTestResolver: GitWorkingCopyResolving {
    let state: GitRepositoryState?
    func discover(containerURL: URL) throws -> GitRepositoryState? { state }
    func prepare(_ copy: GitWorkingCopy, for containerURL: URL, worktreesDirectory: URL) throws -> URL {
        try XCTUnwrap(copy.containerURL)
    }
}

private final class MenuTestLauncher: ProjectLaunching, @unchecked Sendable {
    let logURL = URL(fileURLWithPath: "/tmp/xplay-menu-test.log")
    func launch(completion: @escaping @Sendable (Result<URL, Error>) -> Void) {}
    func cancel() {}
}

private final class URLRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []
    func append(_ value: URL) { lock.lock(); defer { lock.unlock() }; storage.append(value) }
    var values: [URL] { lock.lock(); defer { lock.unlock() }; return storage }
}

private final class RecoveringMenuResolver: GitWorkingCopyResolving, @unchecked Sendable {
    let state: GitRepositoryState
    private let lock = NSLock()
    private var fails = false
    init(state: GitRepositoryState) { self.state = state }
    func setFailure(_ value: Bool) { lock.lock(); defer { lock.unlock() }; fails = value }
    func discover(containerURL: URL) throws -> GitRepositoryState? {
        lock.lock(); defer { lock.unlock() }
        if fails { throw GitWorkingCopyResolver.ResolverError.timedOut }
        return state
    }
    func prepare(_ copy: GitWorkingCopy, for containerURL: URL, worktreesDirectory: URL) throws -> URL {
        try XCTUnwrap(copy.containerURL)
    }
}
