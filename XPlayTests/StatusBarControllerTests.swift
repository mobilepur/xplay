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
    func testMenuBarChoicesUpdateVisibleContentAndKeepXPlayFallback() throws {
        try withState { catalog, settings in
            let phone = XcodeDestination(platform: .iOSSimulator, id: "phone", name: "iPhone 17 Pro")
            configure(catalog, schemes: ["Example-iOS"], destinations: [[phone]])
            let controller = StatusBarController(projectCatalog: catalog, appSettings: settings)
            let button = try XCTUnwrap(controller.statusItem.button)
            let views = descendants(of: button)
            let logo = try XCTUnwrap(views.first { $0.identifier?.rawValue == "xplay-status-icon" })
            let device = try XCTUnwrap(views.first { $0.identifier?.rawValue == "destination-status-icon" })
            let name = try XCTUnwrap(views.compactMap { $0 as? NSTextField }.first {
                $0.identifier?.rawValue == "status-project-name"
            })
            XCTAssertFalse(logo.isHiddenOrHasHiddenAncestor)
            XCTAssertTrue(device.isHiddenOrHasHiddenAncestor)
            XCTAssertTrue(name.isHiddenOrHasHiddenAncestor)

            for (index, mode) in AppSettings.MenuBarContent.allCases.enumerated() {
                let submenu = try XCTUnwrap(controller.contextMenu.items.first {
                    $0.title == "Menu Bar Icon"
                }?.submenu)
                XCTAssertEqual(submenu.items.map(\.title), ["XPlay", "Name + Target", "Name", "Target"])
                submenu.performActionForItem(at: index)
                XCTAssertEqual(settings.menuBarContent, mode)
                XCTAssertEqual(logo.isHiddenOrHasHiddenAncestor, mode != .xplay)
                XCTAssertEqual(device.isHiddenOrHasHiddenAncestor, mode == .xplay || mode == .name)
                XCTAssertEqual(name.isHiddenOrHasHiddenAncestor, mode == .xplay || mode == .target)
                XCTAssertEqual(name.stringValue, "Example")
                let updated = try XCTUnwrap(controller.contextMenu.items.first {
                    $0.title == "Menu Bar Icon"
                }?.submenu)
                XCTAssertEqual(updated.items[index].state, .on)
            }

            catalog.setSchemeEnabled(false, scheme: "Example-iOS", forProjectAt: 0)
            controller.refreshConfiguration()
            XCTAssertFalse(logo.isHiddenOrHasHiddenAncestor)
            XCTAssertTrue(device.isHiddenOrHasHiddenAncestor)
        }
    }

    @MainActor
    func testClickSettingsUpdateRoutingAndMenuAccessHint() throws {
        try withState { catalog, settings in
            let controller = StatusBarController(projectCatalog: catalog, appSettings: settings)
            let right = try XCTUnwrap(controller.contextMenu.items.first { $0.title == "Right Click" }?.submenu)
            XCTAssertEqual(right.items.map(\.title), ["Play", "Menu"])
            right.performActionForItem(at: 0)
            XCTAssertEqual(settings.rightClickAction, .play)
            XCTAssertEqual(settings.leftClickAction, .menu)
            XCTAssertEqual(controller.statusItem.button?.accessibilityLabel(), "Open XPlay menu")
            XCTAssertTrue(controller.statusItem.button?.toolTip?.contains("Left-click for menu") == true)
            let left = try XCTUnwrap(controller.contextMenu.items.first { $0.title == "Left Click" }?.submenu)
            XCTAssertEqual(left.items[1].state, .on)
            XCTAssertEqual(StatusBarController.interaction(for: .leftMouseUp,
                leftClickAction: settings.leftClickAction, rightClickAction: settings.rightClickAction), .showContextMenu)
            XCTAssertEqual(StatusBarController.interaction(for: .rightMouseUp,
                leftClickAction: settings.leftClickAction, rightClickAction: settings.rightClickAction), .startProject)
            let refreshedRight = try XCTUnwrap(controller.contextMenu.items.first { $0.title == "Right Click" }?.submenu)
            refreshedRight.performActionForItem(at: 1)
            XCTAssertEqual(settings.leftClickAction, .play)
            XCTAssertEqual(settings.rightClickAction, .menu)
            XCTAssertNil(StatusBarController.interaction(for: .mouseMoved))
        }
    }

    @MainActor
    func testSettingsRowsShowCurrentValuesBeforeChevronAndUpdateTogether() throws {
        try withState { catalog, settings in
            let controller = StatusBarController(projectCatalog: catalog, appSettings: settings)
            @MainActor func verifyRow(_ title: String, value: String) throws {
                let menu = controller.contextMenu
                let item = try XCTUnwrap(menu.items.first { $0.title == title })
                let row = try XCTUnwrap(item.view)
                row.frame.size.width = 320
                row.layoutSubtreeIfNeeded()
                let labels = row.subviews.compactMap { $0 as? NSTextField }
                let titleLabel = try XCTUnwrap(labels.first { $0.stringValue == title })
                let valueLabel = try XCTUnwrap(labels.first { $0.stringValue == value })
                let chevron = try XCTUnwrap(row.subviews.first { $0.identifier?.rawValue == "setting-chevron" })
                XCTAssertEqual(valueLabel.textColor, .secondaryLabelColor)
                XCTAssertEqual(valueLabel.alignment, .right)
                for width: CGFloat in [320, 336, 500] {
                    row.frame.size.width = width
                    row.layoutSubtreeIfNeeded()
                    XCTAssertGreaterThanOrEqual(valueLabel.frame.width, ceil(try XCTUnwrap(valueLabel.cell).cellSize.width))
                }
                XCTAssertGreaterThanOrEqual(valueLabel.frame.minX, titleLabel.frame.maxX + 8)
                XCTAssertLessThan(valueLabel.frame.maxX, chevron.frame.minX)
                XCTAssertFalse(chevron.isHidden)
                XCTAssertEqual(item.submenu?.items.first { $0.state == .on }?.title, value)
                menu.delegate?.menu?(menu, willHighlight: item)
                XCTAssertEqual(valueLabel.textColor, .selectedMenuItemTextColor)
                menu.delegate?.menu?(menu, willHighlight: nil)
                XCTAssertEqual(valueLabel.textColor, .secondaryLabelColor)
            }
            try verifyRow("Menu Bar Icon", value: "XPlay")
            try verifyRow("Left Click", value: "Play")
            try verifyRow("Right Click", value: "Menu")
            let displayChoices = try XCTUnwrap(controller.contextMenu.items.first { $0.title == "Menu Bar Icon" }?.submenu)
            displayChoices.performActionForItem(at: 1)
            try verifyRow("Menu Bar Icon", value: "Name + Target")
            let leftChoices = try XCTUnwrap(controller.contextMenu.items.first { $0.title == "Left Click" }?.submenu)
            leftChoices.performActionForItem(at: 1)
            try verifyRow("Left Click", value: "Menu")
            try verifyRow("Right Click", value: "Play")
            let rightChoices = try XCTUnwrap(controller.contextMenu.items.first { $0.title == "Right Click" }?.submenu)
            rightChoices.performActionForItem(at: 1)
            try verifyRow("Left Click", value: "Play")
            try verifyRow("Right Click", value: "Menu")
        }
    }

    @MainActor
    func testRunAndStopButtonsLaunchAndCancelSelection() throws {
        try withState { catalog, settings in
            var plans: [XcodeProjectLaunchPlan] = []
            let launcher = DeferredProjectLauncher()
            let controller = StatusBarController(projectCatalog: catalog, appSettings: settings,
                makeLauncher: { plan in
                    plans.append(plan)
                    return launcher
                })
            let item = try XCTUnwrap(controller.contextMenu.items.first { $0.title == "Run Project" })
            let row = try XCTUnwrap(item.view)
            let buttons = descendants(of: row).compactMap { $0 as? NSButton }
            let play = try XCTUnwrap(buttons.first { $0.title == "Run Project" })
            let stop = try XCTUnwrap(buttons.first {
                $0.identifier?.rawValue == "stop-project-button"
            })
            let spinner = try XCTUnwrap(
                descendants(of: play).compactMap { $0 as? NSProgressIndicator }.first {
                    $0.identifier?.rawValue == "run-project-spinner"
                }
            )
            XCTAssertTrue(play.superview === row)
            XCTAssertTrue(stop.superview === row)
            row.frame.size.width = 320
            row.layoutSubtreeIfNeeded()
            XCTAssertGreaterThanOrEqual(row.frame.height, 48)
            XCTAssertLessThan(play.frame.maxX, stop.frame.minX)
            XCTAssertGreaterThanOrEqual(play.frame.width, play.intrinsicContentSize.width)
            XCTAssertEqual(stop.frame.width, 44, accuracy: 0.5)
            XCTAssertEqual(play.title, "Run Project")
            XCTAssertEqual(play.font, .systemFont(ofSize: 16, weight: .medium))
            XCTAssertEqual(play.image?.name(), NSImage.Name("XPlayIcon"))
            XCTAssertEqual(play.image?.size, NSSize(width: 21, height: 18))
            XCTAssertTrue(play.image?.isTemplate == true)
            XCTAssertEqual(stop.title, "")
            XCTAssertEqual(stop.imagePosition, .imageOnly)
            XCTAssertEqual(stop.accessibilityLabel(), "Stop")
            XCTAssertLessThan(
                stop.contentCompressionResistancePriority(for: .horizontal),
                .required
            )
            XCTAssertTrue(spinner.isHidden)
            XCTAssertFalse(play.isEnabled)
            XCTAssertFalse(stop.isEnabled)
            XCTAssertFalse(item.isEnabled)
            let mac = XcodeDestination(platform: .macOS, id: "mac", name: "My Mac")
            configure(catalog, schemes: ["Example-macOS"], destinations: [[mac]])
            controller.refreshConfiguration()
            XCTAssertTrue(play.isEnabled)
            XCTAssertFalse(stop.isEnabled)
            XCTAssertTrue(item.isEnabled)
            play.performClick(nil)
            XCTAssertEqual(plans.map(\.scheme), ["Example-macOS"])
            XCTAssertFalse(play.isEnabled)
            XCTAssertTrue(stop.isEnabled)
            XCTAssertTrue(item.isEnabled)
            XCTAssertEqual(play.title, "Run Project")
            XCTAssertFalse(spinner.isHidden)
            stop.performClick(nil)
            XCTAssertEqual(plans.count, 1)
            XCTAssertEqual(launcher.cancelCount, 1)
            XCTAssertTrue(play.isEnabled)
            XCTAssertFalse(stop.isEnabled)
            XCTAssertTrue(spinner.isHidden)
        }
    }

    @MainActor
    func testPlayInteractionStopsAnActiveLaunchOnSecondClick() {
        withState { catalog, settings in
            let mac = XcodeDestination(platform: .macOS, id: "mac", name: "My Mac")
            configure(catalog, schemes: ["Example-macOS"], destinations: [[mac]])
            let launcher = DeferredProjectLauncher()
            let controller = StatusBarController(
                projectCatalog: catalog,
                appSettings: settings,
                makeLauncher: { _ in launcher }
            )

            controller.perform(.startProject)
            controller.perform(.startProject)

            XCTAssertEqual(launcher.cancelCount, 1)
            XCTAssertEqual(controller.statusItem.button?.accessibilityLabel(), "Start project")
        }
    }

    @MainActor
    func testCancelledLaunchCompletionCannotReplaceANewerLaunch() async throws {
        let suiteName = "StatusBarControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let catalog = ProjectCatalog(defaults: defaults, storageKey: "projects")
        let settings = AppSettings(defaults: defaults, storageKey: "settings")
        let mac = XcodeDestination(platform: .macOS, id: "mac", name: "My Mac")
        configure(catalog, schemes: ["Example-macOS"], destinations: [[mac]])
        let firstLauncher = DeferredProjectLauncher()
        let secondLauncher = DeferredProjectLauncher()
        var launchers: [DeferredProjectLauncher] = [firstLauncher, secondLauncher]
        var presentedFailureCount = 0
        let controller = StatusBarController(
            projectCatalog: catalog,
            appSettings: settings,
            makeLauncher: { _ in launchers.removeFirst() },
            presentLaunchFailures: { presentedFailureCount += $0.count }
        )
        let row = try XCTUnwrap(
            controller.contextMenu.items.first { $0.title == "Run Project" }?.view
        )
        let stop = try XCTUnwrap(
            descendants(of: row).compactMap { $0 as? NSButton }.first {
                $0.identifier?.rawValue == "stop-project-button"
            }
        )

        controller.perform(.startProject)
        controller.perform(.startProject)
        controller.perform(.startProject)
        firstLauncher.complete(.failure(TestLaunchError.failed))
        await Task.yield()
        await Task.yield()

        XCTAssertTrue(stop.isEnabled)
        XCTAssertEqual(presentedFailureCount, 0)
        XCTAssertEqual(secondLauncher.cancelCount, 0)

        secondLauncher.complete(.success(secondLauncher.logURL))
        let finished = expectation(
            for: NSPredicate { _, _ in !stop.isEnabled },
            evaluatedWith: nil
        )
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(presentedFailureCount, 0)
    }

    @MainActor
    func testAllDisplayModesKeepLoadingDotsVisibleAndWidthStable() throws {
        for mode in AppSettings.MenuBarContent.allCases {
            try withState { catalog, settings in
                settings.setMenuBarContent(mode)
                let mac = XcodeDestination(platform: .macOS, id: "mac", name: "My Mac")
                configure(catalog, schemes: ["Example"], destinations: [[mac]])
                let controller = StatusBarController(projectCatalog: catalog, appSettings: settings,
                    makeLauncher: { _ in DeferredProjectLauncher() })
                let length = controller.statusItem.length
                controller.perform(.startProject)
                let button = try XCTUnwrap(controller.statusItem.button)
                button.layoutSubtreeIfNeeded()
                let views = descendants(of: button)
                let dots = try XCTUnwrap(views.first { $0.identifier?.rawValue == "running-dots" })
                XCTAssertFalse(dots.isHiddenOrHasHiddenAncestor, mode.rawValue)
                XCTAssertEqual(length, controller.statusItem.length, mode.rawValue)
                XCTAssertEqual(dots.subviews.count, 3)
                XCTAssertTrue(dots.subviews.allSatisfy { $0.layer?.animation(forKey: "pulse") != nil })
                let dotsRect = dots.convert(dots.bounds, to: button)
                XCTAssertGreaterThanOrEqual(dotsRect.minY, 0)
                XCTAssertLessThanOrEqual(dotsRect.maxY, button.bounds.height)
                if mode == .target || mode == .nameAndTarget {
                    let device = try XCTUnwrap(views.first { $0.identifier?.rawValue == "destination-status-icon" })
                    let content = try XCTUnwrap(views.first { $0.identifier?.rawValue == "status-content" })
                    XCTAssertLessThan(dots.convert(dots.bounds, to: content).maxY,
                                      device.convert(device.bounds, to: content).minY)
                }
            }
        }
    }

    @MainActor
    func testLongProjectNameStaysCompactAndDisplayCanChangeDuringLaunch() throws {
        try withState { catalog, settings in
            settings.setMenuBarContent(.nameAndTarget)
            let name = String(repeating: "LongProject", count: 12)
            catalog.add(URL(fileURLWithPath: "/Projects/\(name).xcworkspace"), schemes: ["Example"])
            catalog.setSchemeEnabled(true, scheme: "Example", forProjectAt: 0)
            catalog.updateDestinations([XcodeDestination(platform: .macOS, id: "mac", name: "My Mac")],
                scheme: "Example", forProjectAt: 0)
            let controller = StatusBarController(projectCatalog: catalog, appSettings: settings,
                makeLauncher: { _ in DeferredProjectLauncher() })
            let button = try XCTUnwrap(controller.statusItem.button)
            button.layoutSubtreeIfNeeded()
            XCTAssertLessThanOrEqual(controller.statusItem.length, 192)
            controller.perform(.startProject)
            let submenu = try XCTUnwrap(controller.contextMenu.items.first { $0.title == "Menu Bar Icon" }?.submenu)
            submenu.performActionForItem(at: 0)
            let views = descendants(of: button)
            XCTAssertFalse(try XCTUnwrap(views.first { $0.identifier?.rawValue == "xplay-status-icon" }).isHiddenOrHasHiddenAncestor)
            XCTAssertFalse(try XCTUnwrap(views.first { $0.identifier?.rawValue == "running-dots" }).isHiddenOrHasHiddenAncestor)
            XCTAssertEqual(controller.statusItem.length, NSStatusItem.squareLength)
        }
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
                "Run Project",
                "",
                "Projects", "No projects yet",
                "",
                "Settings", "Menu Bar Icon", "Left Click", "Right Click", "Accept Macros",
                "",
                "About", "XPlay", "Report a Problem…",
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
        let quit = try XCTUnwrap(items.first { $0.title == "Quit" })
        XCTAssertEqual(quit.keyEquivalent, "q")
        XCTAssertNotEqual(quit.action, #selector(NSApplication.terminate(_:)))
        XCTAssertNil(quit.image)
        let quitRow = try XCTUnwrap(quit.view)
        XCTAssertTrue(quitRow.subviews.compactMap { $0 as? NSImageView }.allSatisfy(\.isHidden))
        XCTAssertTrue(quitRow.subviews.compactMap { $0 as? NSTextField }.contains {
            $0.stringValue == "⌘Q" && $0.textColor == .secondaryLabelColor
        })
    }

    @MainActor
    func testAboutSectionShowsVersionAndOpensReleaseNotesAndIssueReporter() throws {
        var openedURLs: [URL] = []
        let controller = StatusBarController(
            appVersion: "1.2.3",
            openExternalURL: { openedURLs.append($0) }
        )
        let menu = controller.contextMenu
        let aboutHeader = try XCTUnwrap(menu.items.first { $0.title == "About" }?.view)
        XCTAssertTrue(aboutHeader.subviews.compactMap { $0 as? NSTextField }.contains {
            $0.stringValue == "About"
        })
        let versionItem = try XCTUnwrap(menu.items.first { $0.title == "XPlay" })
        let versionRow = try XCTUnwrap(versionItem.view)
        XCTAssertTrue(versionRow.subviews.compactMap { $0 as? NSTextField }.contains {
            $0.stringValue == "1.2.3" && $0.textColor == .secondaryLabelColor
        })
        XCTAssertNotNil(versionRow.subviews.first {
            $0.identifier?.rawValue == "navigation-chevron"
        })
        let versionLink = try XCTUnwrap(
            descendants(of: versionRow).compactMap { $0 as? NSButton }.first {
                $0.identifier?.rawValue == "external-link-button"
            }
        )
        let reportItem = try XCTUnwrap(menu.items.first { $0.title == "Report a Problem…" })
        let reportRow = try XCTUnwrap(reportItem.view)
        XCTAssertNotNil(reportRow.subviews.first {
            $0.identifier?.rawValue == "navigation-chevron"
        })
        let reportLink = try XCTUnwrap(
            descendants(of: reportRow).compactMap { $0 as? NSButton }.first {
                $0.identifier?.rawValue == "external-link-button"
            }
        )

        versionLink.performClick(nil)
        reportLink.performClick(nil)

        XCTAssertEqual(openedURLs.map(\.absoluteString), [
            "https://github.com/mobilepur/xplay/releases/tag/v1.2.3",
            "https://github.com/mobilepur/xplay/issues/new",
        ])
    }

    @MainActor
    func testDevelopmentAboutRowOpensGeneralReleasesPage() throws {
        var openedURLs: [URL] = []
        let controller = StatusBarController(
            appVersion: nil,
            openExternalURL: { openedURLs.append($0) }
        )
        let versionItem = try XCTUnwrap(controller.contextMenu.items.first { $0.title == "XPlay" })
        let versionRow = try XCTUnwrap(versionItem.view)
        XCTAssertTrue(versionRow.subviews.compactMap { $0 as? NSTextField }.contains {
            $0.stringValue == "Development"
        })
        let versionLink = try XCTUnwrap(
            descendants(of: versionRow).compactMap { $0 as? NSButton }.first {
                $0.identifier?.rawValue == "external-link-button"
            }
        )

        versionLink.performClick(nil)

        XCTAssertEqual(openedURLs.first?.absoluteString,
                       "https://github.com/mobilepur/xplay/releases")
    }

    @MainActor
    func testSelectedProjectListsEnabledSchemesAndDestinations() throws {
        try withState { catalog, settings in
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
                descendants(of: try XCTUnwrap(items[1].view))
                    .compactMap { $0 as? NSButton }
                    .first { $0.identifier?.rawValue == "destination-menu-button" }?
                    .menu?.items.map(\.title),
                ["My Mac"]
            )
            XCTAssertEqual(
                descendants(of: try XCTUnwrap(items[2].view))
                    .compactMap { $0 as? NSButton }
                    .first { $0.identifier?.rawValue == "destination-menu-button" }?
                    .menu?.items.map(\.title),
                ["iPhone 17 Pro (26.0)"]
            )
            XCTAssertEqual(
                descendants(of: try XCTUnwrap(items[1].view))
                    .compactMap { $0 as? NSButton }
                    .first { $0.identifier?.rawValue == "destination-menu-button" }?
                    .menu?.items.first { $0.title == "My Mac" }?.state,
                .on
            )
            XCTAssertNil(items[1].submenu)
            XCTAssertNil(items[2].submenu)
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
            let buttons = descendants(of: row).compactMap { $0 as? NSButton }
            let schemeButton = try XCTUnwrap(buttons.first {
                $0.identifier?.rawValue == "scheme-selection-button"
            })
            let destinationButton = try XCTUnwrap(buttons.first {
                $0.identifier?.rawValue == "destination-menu-button"
            })
            XCTAssertEqual(schemeButton.frame.maxX, destinationButton.frame.minX, accuracy: 0.5)
            XCTAssertTrue(schemeButton.frame.contains(
                NSPoint(x: schemeLabel.frame.midX, y: schemeLabel.frame.midY)
            ))
            XCTAssertTrue(destinationButton.frame.contains(
                NSPoint(x: destinationLabel.frame.midX, y: destinationLabel.frame.midY)
            ))
            XCTAssertTrue(destinationButton.frame.contains(
                NSPoint(x: chevron.frame.midX, y: chevron.frame.midY)
            ))
            XCTAssertNil(item.submenu)
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
            var presentedDeviceMenuCount = 0
            let controller = StatusBarController(
                projectCatalog: catalog,
                appSettings: settings,
                presentDestinationMenu: { _, _ in
                    presentedDeviceMenuCount += 1
                }
            )
            let iosItem = try XCTUnwrap(
                controller.contextMenu.items.first { $0.title.hasPrefix("Example-iOS") }
            )
            let row = try XCTUnwrap(iosItem.view)
            let schemeButton = try XCTUnwrap(
                descendants(of: row).compactMap { $0 as? NSButton }.first {
                    $0.identifier?.rawValue == "scheme-selection-button"
                }
            )

            schemeButton.performClick(nil)

            XCTAssertEqual(
                catalog.selectedProject?.selectedLaunchConfiguration?.scheme,
                "Example-iOS"
            )
            XCTAssertEqual(presentedDeviceMenuCount, 0)
            let refreshedSchemes = controller.contextMenu.items.filter {
                $0.title.hasPrefix("Example-")
            }
            XCTAssertEqual(refreshedSchemes.map(\.state), [.off, .on])
        }
    }

    @MainActor
    func testSelectingDestinationFromRightSideMenuPersistsSelection() throws {
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
            var presentedMenu: NSMenu?
            let controller = StatusBarController(
                projectCatalog: catalog,
                appSettings: settings,
                presentDestinationMenu: { menu, _ in
                    presentedMenu = menu
                }
            )
            let schemeItem = try XCTUnwrap(
                controller.contextMenu.items.first { $0.title.hasPrefix("Example-iOS") }
            )
            let row = try XCTUnwrap(schemeItem.view)
            let destinationButton = try XCTUnwrap(
                descendants(of: row).compactMap { $0 as? NSButton }.first {
                    $0.identifier?.rawValue == "destination-menu-button"
                }
            )

            destinationButton.performClick(nil)

            let submenu = try XCTUnwrap(presentedMenu)
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
    func testStatusShowsSelectedDeviceAndHidesItWithoutASelection() throws {
        try withState { catalog, settings in
            let cases: [(XcodeDestination, String)] = [
                (XcodeDestination(platform: .macOS, id: "mac", name: "My Mac"), "Mac"),
                (XcodeDestination(platform: .iOSSimulator, id: "phone", name: "iPhone 17 Pro"), "iPhone"),
                (XcodeDestination(platform: .iOSSimulator, id: "pad", name: "iPad Pro (M4)"), "iPad"),
                (XcodeDestination(platform: .iOSSimulator, id: "custom", name: "QA device"), "iOS Simulator"),
            ]
            settings.setMenuBarContent(.target)
            configure(catalog, schemes: ["Example"], destinations: [cases.map { $0.0 }])
            let controller = StatusBarController(projectCatalog: catalog, appSettings: settings)
            let button = try XCTUnwrap(controller.statusItem.button)
            let views = descendants(of: button)
            let device = try XCTUnwrap(views.compactMap { $0 as? NSImageView }.first {
                $0.identifier?.rawValue == "destination-status-icon"
            })
            let logo = try XCTUnwrap(views.compactMap { $0 as? NSImageView }.first {
                $0.identifier?.rawValue == "xplay-status-icon"
            })
            let dots = try XCTUnwrap(views.first { $0.identifier?.rawValue == "running-dots" })

            XCTAssertTrue(device.isHiddenOrHasHiddenAncestor)
            XCTAssertTrue(dots.isHiddenOrHasHiddenAncestor)
            XCTAssertEqual(controller.statusItem.length, NSStatusItem.squareLength)

            for (destination, label) in cases {
                catalog.selectDestination(id: destination.id, scheme: "Example", forProjectAt: 0)
                controller.refreshConfiguration()
                button.layoutSubtreeIfNeeded()

                XCTAssertFalse(device.isHiddenOrHasHiddenAncestor)
                XCTAssertEqual(device.image?.accessibilityDescription, label)
                XCTAssertEqual(device.accessibilityLabel(), destination.displayName)
                XCTAssertNotNil(logo.image)
                XCTAssertTrue(logo.isHiddenOrHasHiddenAncestor)
                XCTAssertTrue(dots.isHiddenOrHasHiddenAncestor)
            }

            catalog.setSchemeEnabled(false, scheme: "Example", forProjectAt: 0)
            controller.refreshConfiguration()
            XCTAssertTrue(device.isHiddenOrHasHiddenAncestor)
            XCTAssertEqual(controller.statusItem.length, NSStatusItem.squareLength)
        }
    }

    @MainActor
    func testRunningStatusShowsThreeAnimatedDotsBelowSelectedDevice() throws {
        let destinations = [
            XcodeDestination(platform: .macOS, id: "mac", name: "My Mac"),
            XcodeDestination(platform: .iOSSimulator, id: "phone", name: "iPhone 17 Pro"),
            XcodeDestination(platform: .iOSSimulator, id: "pad", name: "iPad Pro"),
            XcodeDestination(platform: .iOSSimulator, id: "custom", name: "QA device"),
        ]
        for destination in destinations {
            try withState { catalog, settings in
                settings.setMenuBarContent(.target)
                configure(catalog, schemes: ["Example"], destinations: [[destination]])
                let controller = StatusBarController(
                    projectCatalog: catalog,
                    appSettings: settings,
                    makeLauncher: { _ in DeferredProjectLauncher() }
                )

                let idleLength = controller.statusItem.length
                controller.perform(.startProject)

                let button = try XCTUnwrap(controller.statusItem.button)
                button.layoutSubtreeIfNeeded()
                let views = descendants(of: button)
                let statusContent = try XCTUnwrap(
                    views.first { $0.identifier?.rawValue == "status-content" }
                )
                let runningIcon = try XCTUnwrap(
                    views.compactMap { $0 as? NSImageView }.first {
                        $0.identifier?.rawValue == "xplay-status-icon"
                    }
                )
                let dots = views.filter {
                    $0.identifier?.rawValue.hasPrefix("running-dot-") == true
                }
                let device = try XCTUnwrap(views.compactMap { $0 as? NSImageView }.first {
                    $0.identifier?.rawValue == "destination-status-icon"
                })
                let deviceRect = device.convert(device.bounds, to: statusContent)

                XCTAssertFalse(statusContent.isHidden)
                XCTAssertNotNil(runningIcon.image)
                XCTAssertEqual(dots.count, 3)
                XCTAssertTrue(dots.allSatisfy { $0.layer?.animation(forKey: "pulse") != nil })
                for dot in dots {
                    XCTAssertFalse(dot.isHiddenOrHasHiddenAncestor)
                    let dotRect = dot.convert(dot.bounds, to: statusContent)
                    XCTAssertLessThan(dotRect.maxY, deviceRect.minY)
                    XCTAssertGreaterThanOrEqual(dotRect.minX, deviceRect.minX)
                    XCTAssertLessThanOrEqual(dotRect.maxX, deviceRect.maxX)
                }
                XCTAssertFalse(device.isHiddenOrHasHiddenAncestor)
                XCTAssertNotNil(device.image)
                XCTAssertTrue(views.compactMap { $0 as? NSProgressIndicator }.isEmpty)
                XCTAssertEqual(controller.statusItem.length, idleLength)
                XCTAssertNil(button.image)
            }
        }
    }

    @MainActor
    func testFinishingLaunchHidesDotsAndRefreshesDeviceAfterSuccessAndFailure() async throws {
        let suiteName = "StatusBarControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let catalog = ProjectCatalog(defaults: defaults, storageKey: "projects")
        let phone = XcodeDestination(platform: .iOSSimulator, id: "phone", name: "iPhone 17 Pro")
        let pad = XcodeDestination(platform: .iOSSimulator, id: "pad", name: "iPad Pro")
        configure(catalog, schemes: ["Example"], destinations: [[phone, pad]])
        let launcher = DeferredProjectLauncher()
        var failureCount = 0
        let settings = AppSettings(defaults: defaults, storageKey: "settings")
        settings.setMenuBarContent(.target)
        let controller = StatusBarController(
            projectCatalog: catalog,
            appSettings: settings,
            makeLauncher: { _ in launcher },
            presentLaunchFailures: { failureCount += $0.count }
        )
        let button = try XCTUnwrap(controller.statusItem.button)
        let views = descendants(of: button)
        let device = try XCTUnwrap(views.compactMap { $0 as? NSImageView }.first {
            $0.identifier?.rawValue == "destination-status-icon"
        })
        let dots = try XCTUnwrap(views.first { $0.identifier?.rawValue == "running-dots" })
        let playRow = try XCTUnwrap(controller.contextMenu.items.first { $0.title == "Run Project" }?.view)
        let play = try XCTUnwrap(
            descendants(of: playRow).compactMap { $0 as? NSButton }.first {
                $0.title == "Run Project"
            }
        )

        for shouldFail in [false, true] {
            catalog.selectDestination(id: phone.id, scheme: "Example", forProjectAt: 0)
            controller.refreshConfiguration()
            controller.perform(.startProject)
            XCTAssertFalse(dots.isHiddenOrHasHiddenAncestor)

            catalog.selectDestination(id: pad.id, scheme: "Example", forProjectAt: 0)
            controller.refreshConfiguration()
            XCTAssertEqual(device.image?.accessibilityDescription, "iPhone")

            launcher.complete(shouldFail ? .failure(TestLaunchError.failed) : .success(launcher.logURL))
            let finished = expectation(
                for: NSPredicate { _, _ in dots.isHidden },
                evaluatedWith: nil
            )
            await fulfillment(of: [finished], timeout: 2)

            XCTAssertEqual(device.image?.accessibilityDescription, "iPad")
            XCTAssertTrue(play.isEnabled)
            XCTAssertEqual(play.title, "Run Project")
            XCTAssertTrue(views.filter {
                $0.identifier?.rawValue.hasPrefix("running-dot-") == true
            }.allSatisfy { $0.layer?.animation(forKey: "pulse") == nil })
        }
        XCTAssertEqual(failureCount, 1)
        catalog.updateDestinations([], scheme: "Example", forProjectAt: 0)
        controller.refreshConfiguration()
        XCTAssertFalse(play.isEnabled)
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

    func cancel() {}
}

private final class DeferredProjectLauncher: ProjectLaunching, @unchecked Sendable {
    let logURL = URL(fileURLWithPath: "/tmp/deferred-build.log")
    private var completion: (@Sendable (Result<URL, Error>) -> Void)?
    private(set) var cancelCount = 0

    func launch(completion: @escaping @Sendable (Result<URL, Error>) -> Void) {
        self.completion = completion
    }

    func complete(_ result: Result<URL, Error>) {
        completion?(result)
        completion = nil
    }

    func cancel() {
        cancelCount += 1
    }
}
