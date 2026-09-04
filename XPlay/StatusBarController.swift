import AppKit

@MainActor
final class StatusBarController: NSObject {
    static let macroWarningText = "Accept Macros skips Xcode validation for all current and future macros in every XPlay project."

    enum Interaction: Equatable {
        case startProject
        case showContextMenu
    }

    struct LaunchFailure {
        let plan: XcodeProjectLaunchPlan
        let error: Error
    }

    private(set) var statusItem: NSStatusItem
    private let progressIndicator: NSProgressIndicator
    private let projectCatalog: ProjectCatalog?
    private let appSettings: AppSettings
    private let onEditProjects: (() -> Void)?
    private let onCatalogChange: (() -> Void)?
    private let confirmMacroAcceptance: () -> Bool
    private let cacheDirectory: URL
    private let makeLauncher: (XcodeProjectLaunchPlan) -> any ProjectLaunching
    private let presentLaunchFailures: ([LaunchFailure]) -> Void
    private var activeLauncher: (any ProjectLaunching)?
    private var isRunning = false

    private(set) lazy var contextMenu = makeContextMenu()

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let projectItem = NSMenuItem(
            title: projectCatalog?.selectedProject?.name ?? "No project selected",
            action: nil,
            keyEquivalent: ""
        )
        projectItem.isEnabled = false
        menu.addItem(projectItem)

        if let project = projectCatalog?.selectedProject {
            let configurations = project.enabledConfigurations
            for configuration in configurations {
                menu.addItem(makeConfigurationItem(configuration, projectURL: project.url))
            }
        }
        menu.addItem(.separator())

        menu.addItem(makeProjectsHeaderItem())

        if let projects = projectCatalog?.projects, !projects.isEmpty {
            for (index, project) in projects.enumerated() {
                let item = NSMenuItem(
                    title: project.name,
                    action: #selector(selectProject(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.tag = index
                item.state = project == projectCatalog?.selectedProject ? .on : .off
                item.isEnabled = true
                menu.addItem(item)
            }
        } else {
            let projectsPlaceholderItem = NSMenuItem(
                title: "No projects yet",
                action: nil,
                keyEquivalent: ""
            )
            projectsPlaceholderItem.isEnabled = false
            projectsPlaceholderItem.indentationLevel = 1
            menu.addItem(projectsPlaceholderItem)
        }
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        settingsItem.isEnabled = false
        menu.addItem(settingsItem)

        let macrosItem = NSMenuItem(
            title: "Accept Macros",
            action: #selector(toggleMacroAcceptance),
            keyEquivalent: ""
        )
        macrosItem.target = self
        macrosItem.state = appSettings.acceptsMacros ? .on : .off
        macrosItem.isEnabled = true
        macrosItem.toolTip = Self.macroWarningText
        menu.addItem(macrosItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp
        quitItem.isEnabled = true
        menu.addItem(quitItem)

        return menu
    }

    private func makeConfigurationItem(
        _ configuration: LaunchConfiguration,
        projectURL: URL
    ) -> NSMenuItem {
        let destinationTitle: String
        if let destination = configuration.selectedDestination {
            destinationTitle = configuration.isSelectedDestinationAvailable
                ? destination.displayName
                : "Unavailable: \(destination.displayName)"
        } else {
            destinationTitle = "Choose Destination…"
        }
        let item = NSMenuItem(
            title: "\(configuration.scheme) — \(destinationTitle)",
            action: nil,
            keyEquivalent: ""
        )
        let submenu = NSMenu(title: configuration.scheme)
        submenu.autoenablesItems = false

        if
            let unavailableDestination = configuration.selectedDestination,
            !configuration.isSelectedDestinationAvailable
        {
            let unavailableItem = NSMenuItem(
                title: "Unavailable: \(unavailableDestination.displayName)",
                action: nil,
                keyEquivalent: ""
            )
            unavailableItem.isEnabled = false
            unavailableItem.state = .on
            submenu.addItem(unavailableItem)
        }

        if configuration.availableDestinations.isEmpty {
            let placeholder = NSMenuItem(
                title: "No destinations available",
                action: nil,
                keyEquivalent: ""
            )
            placeholder.isEnabled = false
            submenu.addItem(placeholder)
        } else {
            for destination in configuration.availableDestinations {
                let destinationItem = NSMenuItem(
                    title: destination.displayName,
                    action: #selector(selectDestination(_:)),
                    keyEquivalent: ""
                )
                destinationItem.target = self
                destinationItem.representedObject = [
                    "projectPath": projectURL.path,
                    "scheme": configuration.scheme,
                    "destinationID": destination.id,
                ]
                destinationItem.state = destination == configuration.selectedDestination ? .on : .off
                destinationItem.isEnabled = true
                submenu.addItem(destinationItem)
            }
        }
        item.submenu = submenu
        return item
    }

    private func makeProjectsHeaderItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Projects", action: nil, keyEquivalent: "")
        item.isEnabled = onEditProjects != nil

        let headerView = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 28))
        headerView.autoresizingMask = [.width]

        let titleLabel = NSTextField(labelWithString: "Projects")
        titleLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let editButton = NSButton(title: "Edit", target: nil, action: nil)
        editButton.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        editButton.isBordered = false
        editButton.target = self
        editButton.action = #selector(editProjects)
        editButton.isEnabled = onEditProjects != nil
        editButton.translatesAutoresizingMaskIntoConstraints = false

        headerView.addSubview(titleLabel)
        headerView.addSubview(editButton)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 12),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            editButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -8),
            editButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: editButton.leadingAnchor, constant: -8),
        ])

        item.view = headerView
        return item
    }

    init(
        projectCatalog: ProjectCatalog? = nil,
        appSettings: AppSettings? = nil,
        onEditProjects: (() -> Void)? = nil,
        onCatalogChange: (() -> Void)? = nil,
        confirmMacroAcceptance: (() -> Bool)? = nil,
        cacheDirectory: URL = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("XPlay", isDirectory: true),
        makeLauncher: @escaping (XcodeProjectLaunchPlan) -> any ProjectLaunching = {
            XcodeProjectLauncher(plan: $0)
        },
        presentLaunchFailures: (([LaunchFailure]) -> Void)? = nil
    ) {
        self.projectCatalog = projectCatalog
        self.appSettings = appSettings ?? AppSettings()
        self.onEditProjects = onEditProjects
        self.onCatalogChange = onCatalogChange
        self.confirmMacroAcceptance = confirmMacroAcceptance ?? Self.presentMacroWarning
        self.cacheDirectory = cacheDirectory
        self.makeLauncher = makeLauncher
        self.presentLaunchFailures = presentLaunchFailures ?? Self.presentDefaultLaunchFailures
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        progressIndicator = NSProgressIndicator()

        super.init()

        guard let button = statusItem.button else {
            return
        }

        button.target = self
        button.action = #selector(handleStatusItemClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isIndeterminate = true
        progressIndicator.isDisplayedWhenStopped = false
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(progressIndicator)

        NSLayoutConstraint.activate([
            progressIndicator.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            progressIndicator.centerYAnchor.constraint(equalTo: button.centerYAnchor),
        ])

        refreshConfiguration()
    }

    private static func presentMacroWarning() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Accept macros in all projects?"
        alert.informativeText = macroWarningText
        alert.addButton(withTitle: "Accept Macros")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func presentDefaultLaunchFailures(_ failures: [LaunchFailure]) {
        guard let firstFailure = failures.first else {
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = failures.count == 1
            ? "The configuration could not be launched"
            : "Some configurations could not be launched"
        alert.informativeText = failures.map { failure in
            "\(failure.plan.scheme): \(failure.error.localizedDescription)"
        }.joined(separator: "\n\n")
        alert.addButton(withTitle: failures.count == 1 ? "Open Build Log" : "Open Logs Folder")
        alert.addButton(withTitle: "OK")

        if alert.runModal() == .alertFirstButtonReturn {
            let url = failures.count == 1
                ? firstFailure.plan.logURL
                : firstFailure.plan.logURL.deletingLastPathComponent()
            NSWorkspace.shared.open(url)
        }
    }

    static func interaction(for eventType: NSEvent.EventType) -> Interaction? {
        switch eventType {
        case .leftMouseUp:
            return .startProject
        case .rightMouseUp:
            return .showContextMenu
        default:
            return nil
        }
    }

    @objc
    private func handleStatusItemClick() {
        guard
            let eventType = NSApp.currentEvent?.type,
            let interaction = Self.interaction(for: eventType)
        else {
            return
        }

        perform(interaction)
    }

    func perform(_ interaction: Interaction) {
        switch interaction {
        case .startProject:
            startProject()
        case .showContextMenu:
            showContextMenu()
        }
    }

    private func startProject() {
        guard
            !isRunning,
            let project = projectCatalog?.selectedProject
        else {
            return
        }
        let plans = XcodeProjectLaunchPlan.makeAll(
            for: project,
            cacheDirectory: cacheDirectory,
            acceptsMacros: appSettings.acceptsMacros
        )
        guard
            !plans.isEmpty,
            plans.count == project.enabledConfigurations.count
        else {
            return
        }

        setRunning(true)
        launchNext(in: plans, at: 0, failures: [])
    }

    private func launchNext(
        in plans: [XcodeProjectLaunchPlan],
        at index: Int,
        failures: [LaunchFailure]
    ) {
        guard plans.indices.contains(index) else {
            activeLauncher = nil
            setRunning(false)
            if !failures.isEmpty {
                presentLaunchFailures(failures)
            }
            return
        }

        let plan = plans[index]
        let launcher = makeLauncher(plan)
        activeLauncher = launcher
        setRunningProgress(plan: plan, index: index, total: plans.count)
        launcher.launch { [weak self] result in
            Task { @MainActor in
                guard let self else {
                    return
                }
                var updatedFailures = failures
                if case let .failure(error) = result {
                    updatedFailures.append(LaunchFailure(plan: plan, error: error))
                }
                self.launchNext(
                    in: plans,
                    at: index + 1,
                    failures: updatedFailures
                )
            }
        }
    }

    private func showContextMenu() {
        contextMenu = makeContextMenu()
        statusItem.menu = contextMenu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc
    private func editProjects() {
        contextMenu.cancelTracking()
        onEditProjects?()
    }

    @objc
    private func selectProject(_ item: NSMenuItem) {
        projectCatalog?.selectProject(at: item.tag)
        onCatalogChange?()
        contextMenu = makeContextMenu()
        refreshConfiguration()
    }

    @objc
    private func selectDestination(_ item: NSMenuItem) {
        guard
            let selection = item.representedObject as? [String: String],
            let projectPath = selection["projectPath"],
            let scheme = selection["scheme"],
            let destinationID = selection["destinationID"],
            let projectIndex = projectCatalog?.projects.firstIndex(where: {
                $0.url.path == projectPath
            })
        else {
            return
        }

        projectCatalog?.selectDestination(
            id: destinationID,
            scheme: scheme,
            forProjectAt: projectIndex
        )
        onCatalogChange?()
        contextMenu = makeContextMenu()
        refreshConfiguration()
    }

    @objc
    private func toggleMacroAcceptance() {
        if appSettings.acceptsMacros {
            appSettings.setAcceptsMacros(false)
        } else {
            guard confirmMacroAcceptance() else {
                return
            }
            appSettings.setAcceptsMacros(true)
        }
        contextMenu = makeContextMenu()
    }

    private func setRunning(_ running: Bool) {
        guard let button = statusItem.button else {
            return
        }

        isRunning = running
        button.setAccessibilityLabel(running ? "Project is starting" : "Start project")
        button.toolTip = running ? "Building and launching project…" : "Start project"

        if running {
            button.image = nil
            progressIndicator.startAnimation(nil)
        } else {
            progressIndicator.stopAnimation(nil)
            refreshConfiguration()
        }
    }

    private func setRunningProgress(
        plan: XcodeProjectLaunchPlan,
        index: Int,
        total: Int
    ) {
        guard isRunning, let button = statusItem.button else {
            return
        }
        let position = "\(index + 1) of \(total)"
        button.setAccessibilityLabel("Starting \(plan.scheme) (\(position))")
        button.toolTip = "Building and launching \(plan.scheme) (\(position))…"
    }

    func refreshConfiguration() {
        guard !isRunning, let button = statusItem.button else {
            return
        }

        let configurations = projectCatalog?.selectedProject?.enabledConfigurations ?? []
        let hasEnabledSchemes = !configurations.isEmpty
        let canStart = hasEnabledSchemes && configurations.allSatisfy {
            $0.isSelectedDestinationAvailable
        }
        let description: String
        if canStart {
            description = "Start project"
        } else if hasEnabledSchemes {
            description = "Choose a destination for every enabled scheme"
        } else {
            description = "No project scheme selected"
        }
        button.image = menuBarImage(named: "play.fill", description: description)
        button.setAccessibilityLabel(canStart ? "Start project" : "\(description). Right-click for menu")
        button.toolTip = canStart
            ? "Start project"
            : "\(description) · Right-click for menu"
    }

    private func menuBarImage(named name: String, description: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: description)
        image?.isTemplate = true
        return image
    }
}
