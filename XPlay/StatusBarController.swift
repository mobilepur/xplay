import AppKit

@MainActor
final class StatusBarController: NSObject {
    enum Interaction: Equatable {
        case startProject
        case showContextMenu
    }

    private let statusItem: NSStatusItem
    private let progressIndicator: NSProgressIndicator
    private let launcher: XcodeProjectLauncher?
    private let projectCatalog: ProjectCatalog?
    private let onEditProjects: (() -> Void)?
    private var isRunning = false

    private(set) lazy var contextMenu = makeContextMenu()

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let projectItem = NSMenuItem(
            title: projectCatalog?.selectedProject?.name ?? launcher?.plan.productName ?? "No project selected",
            action: nil,
            keyEquivalent: ""
        )
        projectItem.isEnabled = false
        menu.addItem(projectItem)
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
        launcher: XcodeProjectLauncher? = nil,
        projectCatalog: ProjectCatalog? = nil,
        onEditProjects: (() -> Void)? = nil
    ) {
        self.launcher = launcher
        self.projectCatalog = projectCatalog
        self.onEditProjects = onEditProjects
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        progressIndicator = NSProgressIndicator()

        super.init()

        guard let button = statusItem.button else {
            return
        }

        button.image = menuBarImage(named: "play.fill", description: "Start project")
        button.setAccessibilityLabel(
            launcher == nil ? "No project selected. Right-click for menu" : "Start project"
        )
        button.toolTip = launcher == nil ? "No project selected · Right-click for menu" : "Start project"
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

        switch interaction {
        case .startProject:
            startProject()
        case .showContextMenu:
            showContextMenu()
        }
    }

    private func startProject() {
        guard !isRunning, let launcher else {
            return
        }

        setRunning(true)

        launcher.launch { [weak self] result in
            Task { @MainActor in
                guard let self else {
                    return
                }

                self.setRunning(false)

                if case let .failure(error) = result {
                    self.showFailure(error, logURL: launcher.logURL)
                }
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
            button.image = menuBarImage(named: "play.fill", description: "Start project")
        }
    }

    private func showFailure(_ error: Error, logURL: URL) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "The project could not be launched"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "Open Build Log")
        alert.addButton(withTitle: "OK")

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(logURL)
        }
    }

    private func menuBarImage(named name: String, description: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: description)
        image?.isTemplate = true
        return image
    }
}
