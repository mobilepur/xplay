import AppKit
import UniformTypeIdentifiers

@MainActor
final class ProjectWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private enum Layout {
        static let windowSize = NSSize(width: 520, height: 400)
        static let minimumWindowSize = NSSize(width: 420, height: 300)
        static let contentInset: CGFloat = 20
        static let projectIconSize: CGFloat = 32
        static let projectRowHeight: CGFloat = 52
        static let removeButtonSize: CGFloat = 24
    }

    private enum Identifier {
        static let projectCell = NSUserInterfaceItemIdentifier("ProjectCell")
        static let projectPath = NSUserInterfaceItemIdentifier("ProjectPath")
        static let removeProject = NSUserInterfaceItemIdentifier("RemoveProject")
    }

    private let catalog: ProjectCatalog

    private(set) lazy var tableView: NSTableView = {
        let tableView = NSTableView(frame: NSRect(origin: .zero, size: Layout.windowSize))
        tableView.headerView = nil
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = true
        tableView.dataSource = self
        tableView.delegate = self
        tableView.autoresizingMask = [.width]
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.backgroundColor = .clear
        tableView.intercellSpacing = NSSize(width: 0, height: 4)
        tableView.rowHeight = Layout.projectRowHeight

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Project"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        return tableView
    }()

    private(set) lazy var titleLabel: NSTextField = {
        let label = NSTextField(labelWithString: "Projects")
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        return label
    }()

    private(set) lazy var addButton: NSButton = {
        let button = NSButton(
            title: "Add Project…",
            target: self,
            action: #selector(chooseProjectFromFinder)
        )
        button.bezelStyle = .rounded
        button.setAccessibilityLabel("Add project")
        return button
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

    init(catalog: ProjectCatalog) {
        self.catalog = catalog
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

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(titleLabel)
        contentView.addSubview(scrollView)
        contentView.addSubview(addButton)
        contentView.addSubview(doneButton)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(
                equalTo: contentView.topAnchor,
                constant: Layout.contentInset
            ),
            titleLabel.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: Layout.contentInset
            ),

            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 14),
            scrollView.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: Layout.contentInset
            ),
            scrollView.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: -Layout.contentInset
            ),
            scrollView.bottomAnchor.constraint(equalTo: addButton.topAnchor, constant: -16),

            addButton.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: Layout.contentInset
            ),
            addButton.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor,
                constant: -Layout.contentInset
            ),

            doneButton.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: -Layout.contentInset
            ),
            doneButton.bottomAnchor.constraint(equalTo: addButton.bottomAnchor),
        ])

        window = panel
        reloadProjects()
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
    }

    func makeProjectOpenPanel() -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.title = "Add Xcode Project"
        panel.message = "Choose an Xcode project to add to XPlay."
        panel.prompt = "Add"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        if let projectType = UTType(filenameExtension: "xcodeproj", conformingTo: .package) {
            panel.allowedContentTypes = [projectType]
        }
        return panel
    }

    func addProject(at url: URL) {
        guard catalog.add(url) else {
            return
        }

        reloadProjects()
        let row = catalog.projects.count - 1
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        catalog.projects.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        let cell = tableView.makeView(
            withIdentifier: Identifier.projectCell,
            owner: self
        ) as? NSTableCellView ?? makeProjectCell()
        let project = catalog.projects[row]

        cell.textField?.stringValue = project.name
        cell.imageView?.image = NSWorkspace.shared.icon(forFile: project.url.path)
        let pathLabel = cell.subviews
            .compactMap { $0 as? NSTextField }
            .first { $0.identifier == Identifier.projectPath }
        pathLabel?.stringValue = project.url.path

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

    func tableViewSelectionDidChange(_ notification: Notification) {
        if tableView.selectedRow >= 0 {
            catalog.selectProject(at: tableView.selectedRow)
        }
    }

    @objc
    private func chooseProjectFromFinder() {
        guard let window else {
            return
        }

        let panel = makeProjectOpenPanel()
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }
            self?.addProject(at: url)
        }
    }

    @objc
    private func removeProject(_ sender: NSButton) {
        guard catalog.removeProject(at: sender.tag) else {
            return
        }
        reloadProjects()
    }

    @objc
    private func closeProjectWindow() {
        close()
    }

    private func reloadProjects() {
        tableView.reloadData()
        tableView.deselectAll(nil)
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
            imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
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

            removeButton.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            removeButton.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            removeButton.widthAnchor.constraint(equalToConstant: Layout.removeButtonSize),
            removeButton.heightAnchor.constraint(equalToConstant: Layout.removeButtonSize),
        ])

        return cell
    }
}
