import AppKit
import UniformTypeIdentifiers

@MainActor
private final class SchemeToggleButton: NSButton {
    var projectURL: URL?
    var scheme: String?
}

@MainActor
private final class DestinationPopUpButton: NSPopUpButton {
    var projectURL: URL?
    var scheme: String?
}

@MainActor
final class ProjectWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    struct ResolutionFailure: Equatable {
        let projectName: String
        let subject: String
        let message: String
    }

    private enum Layout {
        static let windowSize = NSSize(width: 620, height: 500)
        static let minimumWindowSize = NSSize(width: 520, height: 400)
        static let contentInset: CGFloat = 20
        static let projectIconSize: CGFloat = 32
        static let projectRowHeight: CGFloat = 52
        static let schemeRowHeight: CGFloat = 38
        static let removeButtonSize: CGFloat = 24
    }

    private enum Identifier {
        static let projectTable = NSUserInterfaceItemIdentifier("ProjectTable")
        static let schemeTable = NSUserInterfaceItemIdentifier("SchemeTable")
        static let projectCell = NSUserInterfaceItemIdentifier("ProjectCell")
        static let projectPath = NSUserInterfaceItemIdentifier("ProjectPath")
        static let removeProject = NSUserInterfaceItemIdentifier("RemoveProject")
        static let schemeCell = NSUserInterfaceItemIdentifier("SchemeCell")
        static let schemeToggle = NSUserInterfaceItemIdentifier("SchemeToggle")
        static let destinationSelector = NSUserInterfaceItemIdentifier("DestinationSelector")
    }

    private struct DestinationRequest: Hashable {
        let projectURL: URL
        let scheme: String
    }

    private let catalog: ProjectCatalog
    private let schemeResolver: XcodeSchemeResolver
    private let presentResolutionFailure: ((ResolutionFailure) -> Bool)?
    private let onCatalogChange: (() -> Void)?
    private var resolvingProjectURLs = Set<URL>()
    private var resolvingDestinations = Set<DestinationRequest>()

    private(set) lazy var projectTableView: NSTableView = {
        let tableView = makeTableView(
            identifier: Identifier.projectTable,
            rowHeight: Layout.projectRowHeight
        )
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Project"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        return tableView
    }()

    private(set) lazy var schemeTableView: NSTableView = {
        let tableView = makeTableView(
            identifier: Identifier.schemeTable,
            rowHeight: Layout.schemeRowHeight
        )
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Scheme"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        return tableView
    }()

    private(set) lazy var addButton: NSButton = {
        let button = NSButton(
            title: "Add Workspace…",
            target: self,
            action: #selector(chooseWorkspaceFromFinder)
        )
        button.bezelStyle = .rounded
        button.setAccessibilityLabel("Add workspace")
        return button
    }()

    private(set) lazy var schemeStatusLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        return label
    }()

    private(set) lazy var doneButton: NSButton = {
        let button = NSButton(
            title: "Done",
            target: self,
            action: #selector(closeProjectWindow)
        )
        button.bezelStyle = .rounded
        button.keyEquivalent = "\r"
        return button
    }()

    init(
        catalog: ProjectCatalog,
        schemeResolver: XcodeSchemeResolver = XcodeSchemeResolver(),
        presentResolutionFailure: ((ResolutionFailure) -> Bool)? = nil,
        onCatalogChange: (() -> Void)? = nil
    ) {
        self.catalog = catalog
        self.schemeResolver = schemeResolver
        self.presentResolutionFailure = presentResolutionFailure
        self.onCatalogChange = onCatalogChange
        super.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadWindow() {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Layout.windowSize),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "XPlay Projects"
        panel.contentMinSize = Layout.minimumWindowSize
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        let contentView = NSView()
        panel.contentView = contentView

        let projectsLabel = sectionLabel("Projects")
        let schemesLabel = sectionLabel("Schemes")
        let projectScrollView = scrollView(for: projectTableView)
        let schemeScrollView = scrollView(for: schemeTableView)

        for view in [
            projectsLabel,
            projectScrollView,
            schemesLabel,
            schemeStatusLabel,
            schemeScrollView,
            addButton,
            doneButton,
        ] {
            view.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(view)
        }

        NSLayoutConstraint.activate([
            projectsLabel.topAnchor.constraint(
                equalTo: contentView.topAnchor,
                constant: Layout.contentInset
            ),
            projectsLabel.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: Layout.contentInset
            ),

            projectScrollView.topAnchor.constraint(equalTo: projectsLabel.bottomAnchor, constant: 8),
            projectScrollView.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: Layout.contentInset
            ),
            projectScrollView.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: -Layout.contentInset
            ),
            projectScrollView.heightAnchor.constraint(equalToConstant: 124),

            schemesLabel.topAnchor.constraint(equalTo: projectScrollView.bottomAnchor, constant: 18),
            schemesLabel.leadingAnchor.constraint(equalTo: projectScrollView.leadingAnchor),

            schemeStatusLabel.centerYAnchor.constraint(equalTo: schemesLabel.centerYAnchor),
            schemeStatusLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: schemesLabel.trailingAnchor,
                constant: 12
            ),
            schemeStatusLabel.trailingAnchor.constraint(equalTo: projectScrollView.trailingAnchor),

            schemeScrollView.topAnchor.constraint(equalTo: schemesLabel.bottomAnchor, constant: 8),
            schemeScrollView.leadingAnchor.constraint(equalTo: projectScrollView.leadingAnchor),
            schemeScrollView.trailingAnchor.constraint(equalTo: projectScrollView.trailingAnchor),
            schemeScrollView.bottomAnchor.constraint(equalTo: addButton.topAnchor, constant: -16),

            addButton.leadingAnchor.constraint(equalTo: projectScrollView.leadingAnchor),
            addButton.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor,
                constant: -Layout.contentInset
            ),

            doneButton.trailingAnchor.constraint(equalTo: projectScrollView.trailingAnchor),
            doneButton.bottomAnchor.constraint(equalTo: addButton.bottomAnchor),
        ])

        window = panel
        reloadTables()
    }

    func showProjects() {
        if window == nil {
            loadWindow()
        }

        let wasVisible = window?.isVisible ?? false
        showWindow(nil)
        if !wasVisible {
            window?.center()
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)

        Task { [weak self] in
            await self?.refreshSchemes()
        }
    }

    func refreshFromCatalog() {
        reloadTables()
    }

    func makeWorkspaceOpenPanel() -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.title = "Add Xcode Workspace"
        panel.message = "Choose an Xcode workspace to add to XPlay."
        panel.prompt = "Add"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        if let workspaceType = UTType(filenameExtension: "xcworkspace", conformingTo: .package) {
            panel.allowedContentTypes = [workspaceType]
        }
        return panel
    }

    func addWorkspace(at url: URL) async {
        guard url.pathExtension.lowercased() == "xcworkspace", catalog.add(url) else {
            return
        }

        onCatalogChange?()
        let workspaceURL = url.standardizedFileURL
        reloadTables()
        guard let row = catalog.projects.firstIndex(where: { $0.url == workspaceURL }) else {
            return
        }
        await refreshSchemes(forProjectAt: row)
        reloadTables()
    }

    func refreshSchemes() async {
        let projectURLs = catalog.projects.map(\.url)
        for projectURL in projectURLs {
            guard let row = catalog.projects.firstIndex(where: { $0.url == projectURL }) else {
                continue
            }
            await refreshSchemes(forProjectAt: row)
        }
        reloadTables()
    }

    func setSchemeEnabled(_ isEnabled: Bool, scheme: String) async {
        guard let projectURL = catalog.selectedProject?.url else {
            return
        }

        await setSchemeEnabled(isEnabled, scheme: scheme, projectURL: projectURL)
    }

    private func setSchemeEnabled(
        _ isEnabled: Bool,
        scheme: String,
        projectURL: URL
    ) async {
        guard
            let projectIndex = catalog.projects.firstIndex(where: { $0.url == projectURL }),
            let project = catalog.projects[safe: projectIndex]
        else {
            return
        }

        catalog.setSchemeEnabled(isEnabled, scheme: scheme, forProjectAt: projectIndex)
        reloadTables()
        onCatalogChange?()

        if isEnabled {
            await refreshDestinations(
                scheme: scheme,
                projectURL: project.url,
                kind: project.kind
            )
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView.identifier == Identifier.projectTable {
            return catalog.projects.count
        }
        return catalog.selectedProject?.configurations.count ?? 0
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        if tableView.identifier == Identifier.projectTable {
            return projectView(row: row)
        }
        return schemeView(row: row)
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard
            let tableView = notification.object as? NSTableView,
            tableView.identifier == Identifier.projectTable,
            tableView.selectedRow >= 0
        else {
            return
        }

        catalog.selectProject(at: tableView.selectedRow)
        schemeTableView.reloadData()
        updateSchemeStatus()
        onCatalogChange?()
    }

    @objc
    private func chooseWorkspaceFromFinder() {
        guard let window else {
            return
        }

        let panel = makeWorkspaceOpenPanel()
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }
            Task { @MainActor [weak self] in
                await self?.addWorkspace(at: url)
            }
        }
    }

    @objc
    private func toggleScheme(_ sender: NSButton) {
        guard
            let sender = sender as? SchemeToggleButton,
            let projectURL = sender.projectURL,
            let scheme = sender.scheme
        else {
            return
        }

        Task { [weak self] in
            await self?.setSchemeEnabled(
                sender.state == .on,
                scheme: scheme,
                projectURL: projectURL
            )
        }
    }

    @objc
    private func selectDestination(_ sender: NSPopUpButton) {
        guard
            let sender = sender as? DestinationPopUpButton,
            let projectURL = sender.projectURL,
            let scheme = sender.scheme,
            let projectIndex = catalog.projects.firstIndex(where: { $0.url == projectURL }),
            let destinationID = sender.selectedItem?.representedObject as? String
        else {
            return
        }

        catalog.selectDestination(
            id: destinationID,
            scheme: scheme,
            forProjectAt: projectIndex
        )
        reloadTables()
        onCatalogChange?()
    }

    @objc
    private func removeProject(_ sender: NSButton) {
        guard catalog.removeProject(at: sender.tag) else {
            return
        }
        reloadTables()
        onCatalogChange?()
    }

    @objc
    private func closeProjectWindow() {
        close()
    }

    private func projectView(row: Int) -> NSView? {
        guard let project = catalog.projects[safe: row] else {
            return nil
        }
        let cell = projectTableView.makeView(
            withIdentifier: Identifier.projectCell,
            owner: self
        ) as? NSTableCellView ?? makeProjectCell()

        cell.textField?.stringValue = project.name
        cell.imageView?.image = NSWorkspace.shared.icon(forFile: project.url.path)
        cell.subviews
            .compactMap { $0 as? NSTextField }
            .first { $0.identifier == Identifier.projectPath }?
            .stringValue = project.url.path

        let removeButton = cell.subviews
            .compactMap { $0 as? NSButton }
            .first { $0.identifier == Identifier.removeProject }
        removeButton?.tag = row
        removeButton?.target = self
        removeButton?.action = #selector(removeProject(_:))
        removeButton?.toolTip = "Remove \(project.name)"
        removeButton?.setAccessibilityLabel("Remove \(project.name)")
        return cell
    }

    private func schemeView(row: Int) -> NSView? {
        guard
            let project = catalog.selectedProject,
            let configuration = project.configurations[safe: row]
        else {
            return nil
        }
        let cell = schemeTableView.makeView(
            withIdentifier: Identifier.schemeCell,
            owner: self
        ) as? NSTableCellView ?? makeSchemeCell()

        let checkbox = cell.subviews
            .compactMap { $0 as? SchemeToggleButton }
            .first { $0.identifier == Identifier.schemeToggle }
        checkbox?.title = configuration.scheme
        checkbox?.state = configuration.isEnabled ? .on : .off
        checkbox?.tag = row
        checkbox?.projectURL = project.url
        checkbox?.scheme = configuration.scheme
        checkbox?.target = self
        checkbox?.action = #selector(toggleScheme(_:))
        checkbox?.setAccessibilityLabel("Enable \(configuration.scheme)")

        let selector = cell.subviews
            .compactMap { $0 as? DestinationPopUpButton }
            .first { $0.identifier == Identifier.destinationSelector }
        selector?.projectURL = project.url
        selector?.scheme = configuration.scheme
        configureDestinationSelector(
            selector,
            project: project,
            configuration: configuration,
            row: row
        )
        return cell
    }

    private func configureDestinationSelector(
        _ selector: DestinationPopUpButton?,
        project: SavedProject,
        configuration: LaunchConfiguration,
        row: Int
    ) {
        guard let selector else {
            return
        }
        selector.removeAllItems()
        selector.tag = row
        selector.target = self
        selector.action = #selector(selectDestination(_:))
        selector.setAccessibilityLabel("Destination for \(configuration.scheme)")

        let request = DestinationRequest(projectURL: project.url, scheme: configuration.scheme)
        if resolvingDestinations.contains(request) {
            if
                configuration.selectedDestination != nil
                    || !configuration.availableDestinations.isEmpty
            {
                addDestinationOptions(to: selector, configuration: configuration)
                selector.menu?.addItem(.separator())
                selector.addItem(withTitle: "Loading destinations…")
                selector.lastItem?.isEnabled = false
                if let destination = configuration.selectedDestination {
                    selector.selectItem(
                        withTitle: configuration.isSelectedDestinationAvailable
                            ? destination.displayName
                            : "Unavailable: \(destination.displayName)"
                    )
                }
            } else {
                selector.addItem(withTitle: "Loading destinations…")
            }
            selector.isEnabled = false
        } else if !configuration.isEnabled {
            selector.addItem(withTitle: "Enable scheme first")
            selector.isEnabled = false
        } else if
            configuration.availableDestinations.isEmpty,
            configuration.selectedDestination == nil
        {
            selector.addItem(withTitle: "No destinations found")
            selector.isEnabled = false
        } else {
            addDestinationOptions(to: selector, configuration: configuration)
            selector.isEnabled = !configuration.availableDestinations.isEmpty
        }
    }

    private func addDestinationOptions(
        to selector: NSPopUpButton,
        configuration: LaunchConfiguration
    ) {
        if
            let unavailableDestination = configuration.selectedDestination,
            !configuration.isSelectedDestinationAvailable
        {
            selector.addItem(withTitle: "Unavailable: \(unavailableDestination.displayName)")
            selector.lastItem?.isEnabled = false
        } else if configuration.selectedDestination == nil {
            selector.addItem(withTitle: "Choose Destination…")
        }
        for destination in configuration.availableDestinations {
            selector.addItem(withTitle: destination.displayName)
            selector.lastItem?.representedObject = destination.id
        }
        if
            let destination = configuration.selectedDestination,
            configuration.isSelectedDestinationAvailable
        {
            selector.selectItem(withTitle: destination.displayName)
        } else {
            selector.selectItem(at: 0)
        }
    }

    private func reloadTables() {
        projectTableView.reloadData()
        if
            let selectedURL = catalog.selectedProject?.url,
            let row = catalog.projects.firstIndex(where: { $0.url == selectedURL })
        {
            projectTableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else {
            projectTableView.deselectAll(nil)
        }
        schemeTableView.reloadData()
        updateSchemeStatus()
    }

    private func updateSchemeStatus() {
        guard let project = catalog.selectedProject else {
            schemeStatusLabel.stringValue = "Select a project"
            schemeStatusLabel.setAccessibilityLabel("Select a project")
            return
        }
        if resolvingProjectURLs.contains(project.url) {
            schemeStatusLabel.stringValue = "Loading schemes…"
            schemeStatusLabel.setAccessibilityLabel("Loading schemes")
        } else if project.configurations.isEmpty {
            schemeStatusLabel.stringValue = "No schemes found"
            schemeStatusLabel.setAccessibilityLabel("No schemes found")
        } else {
            schemeStatusLabel.stringValue = ""
            schemeStatusLabel.setAccessibilityLabel(nil)
        }
    }

    private func makeTableView(
        identifier: NSUserInterfaceItemIdentifier,
        rowHeight: CGFloat
    ) -> NSTableView {
        let tableView = NSTableView()
        tableView.identifier = identifier
        tableView.headerView = nil
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = true
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .clear
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.rowHeight = rowHeight
        return tableView
    }

    private func scrollView(for tableView: NSTableView) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.drawsBackground = false
        return scrollView
    }

    private func sectionLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        return label
    }

    private func makeProjectCell() -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = Identifier.projectCell

        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = NSTextField(labelWithString: "")
        nameLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        let pathLabel = NSTextField(labelWithString: "")
        pathLabel.identifier = Identifier.projectPath
        pathLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.translatesAutoresizingMaskIntoConstraints = false

        let removeButton = NSButton(
            image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Remove project")
                ?? NSImage(),
            target: nil,
            action: nil
        )
        removeButton.identifier = Identifier.removeProject
        removeButton.isBordered = false
        removeButton.imagePosition = .imageOnly
        removeButton.contentTintColor = .secondaryLabelColor
        removeButton.translatesAutoresizingMaskIntoConstraints = false

        cell.addSubview(imageView)
        cell.addSubview(nameLabel)
        cell.addSubview(pathLabel)
        cell.addSubview(removeButton)
        cell.imageView = imageView
        cell.textField = nameLabel

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: Layout.projectIconSize),
            imageView.heightAnchor.constraint(equalToConstant: Layout.projectIconSize),

            nameLabel.topAnchor.constraint(equalTo: cell.topAnchor, constant: 6),
            nameLabel.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 10),
            nameLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: removeButton.leadingAnchor,
                constant: -10
            ),

            pathLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            pathLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            pathLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: removeButton.leadingAnchor,
                constant: -10
            ),

            removeButton.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            removeButton.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            removeButton.widthAnchor.constraint(equalToConstant: Layout.removeButtonSize),
            removeButton.heightAnchor.constraint(equalToConstant: Layout.removeButtonSize),
        ])
        return cell
    }

    private func makeSchemeCell() -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = Identifier.schemeCell

        let checkbox = SchemeToggleButton(checkboxWithTitle: "", target: nil, action: nil)
        checkbox.identifier = Identifier.schemeToggle
        checkbox.translatesAutoresizingMaskIntoConstraints = false

        let selector = DestinationPopUpButton(frame: .zero, pullsDown: false)
        selector.identifier = Identifier.destinationSelector
        selector.controlSize = .small
        selector.translatesAutoresizingMaskIntoConstraints = false

        cell.addSubview(checkbox)
        cell.addSubview(selector)
        NSLayoutConstraint.activate([
            checkbox.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            checkbox.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            checkbox.trailingAnchor.constraint(lessThanOrEqualTo: selector.leadingAnchor, constant: -12),

            selector.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            selector.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            selector.widthAnchor.constraint(equalToConstant: 220),
        ])
        return cell
    }

    private func refreshSchemes(forProjectAt row: Int) async {
        guard let project = catalog.projects[safe: row] else {
            return
        }
        guard !resolvingProjectURLs.contains(project.url) else {
            return
        }

        resolvingProjectURLs.insert(project.url)
        reloadTables()
        defer {
            resolvingProjectURLs.remove(project.url)
            reloadTables()
        }

        let resolver = schemeResolver
        do {
            let schemes = try await Task.detached(priority: .userInitiated) {
                try resolver.schemes(for: project.url, kind: project.kind)
            }.value
            guard let currentRow = catalog.projects.firstIndex(where: { $0.url == project.url }) else {
                return
            }
            catalog.updateSchemes(schemes, forProjectAt: currentRow)
            onCatalogChange?()

            let enabledSchemes = catalog.projects[currentRow].enabledConfigurations.map(\.scheme)
            for scheme in enabledSchemes {
                await refreshDestinations(
                    scheme: scheme,
                    projectURL: project.url,
                    kind: project.kind
                )
            }
        } catch {
            resolvingProjectURLs.remove(project.url)
            reloadTables()
            if shouldRetryResolution(
                error,
                projectName: project.name,
                subject: "schemes"
            ), let currentRow = catalog.projects.firstIndex(where: { $0.url == project.url }) {
                await refreshSchemes(forProjectAt: currentRow)
            }
        }
    }

    private func refreshDestinations(
        scheme: String,
        projectURL: URL,
        kind: XcodeContainerKind
    ) async {
        let request = DestinationRequest(projectURL: projectURL, scheme: scheme)
        guard !resolvingDestinations.contains(request) else {
            return
        }

        resolvingDestinations.insert(request)
        schemeTableView.reloadData()
        defer {
            resolvingDestinations.remove(request)
            schemeTableView.reloadData()
        }

        let resolver = schemeResolver
        do {
            let destinations = try await Task.detached(priority: .userInitiated) {
                try resolver.destinations(for: projectURL, kind: kind, scheme: scheme)
            }.value
            guard let projectIndex = catalog.projects.firstIndex(where: { $0.url == projectURL }) else {
                return
            }
            catalog.updateDestinations(destinations, scheme: scheme, forProjectAt: projectIndex)
            onCatalogChange?()
        } catch {
            let projectName = projectURL.deletingPathExtension().lastPathComponent
            resolvingDestinations.remove(request)
            schemeTableView.reloadData()
            if shouldRetryResolution(
                error,
                projectName: projectName,
                subject: "destinations"
            ) {
                await refreshDestinations(
                    scheme: scheme,
                    projectURL: projectURL,
                    kind: kind
                )
            }
        }
    }

    private func shouldRetryResolution(
        _ error: Error,
        projectName: String,
        subject: String
    ) -> Bool {
        let failure = ResolutionFailure(
            projectName: projectName,
            subject: subject,
            message: error.localizedDescription
        )
        if let presentResolutionFailure {
            return presentResolutionFailure(failure)
        }

        guard let window, window.isVisible else {
            return false
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Could not read \(subject) for \(projectName)"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "Retry")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
