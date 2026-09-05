import AppKit

@MainActor
private final class ConfigurationActionButton: NSButton {
    var representedSelection: [String: String]?
}

@MainActor
private final class MenuDetailItemView: NSView {
    private let titleLabel: NSTextField
    private let detailLabel: NSTextField
    private let checkmark: NSImageView
    private let chevron: NSImageView
    private var isMenuHighlighted = false

    init(
        title: String,
        detail: String,
        selection: Bool? = nil,
        chevronIdentifier: String? = nil,
        showsChevron: Bool = true
    ) {
        titleLabel = NSTextField(labelWithString: title)
        detailLabel = NSTextField(labelWithString: detail)
        checkmark = NSImageView()
        chevron = NSImageView()

        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: 28))

        autoresizingMask = [.width]

        checkmark.identifier = NSUserInterfaceItemIdentifier("configuration-checkmark")
        checkmark.image = NSImage(
            systemSymbolName: "checkmark",
            accessibilityDescription: nil
        )
        checkmark.isHidden = selection != true
        checkmark.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .menuFont(ofSize: NSFont.systemFontSize)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        detailLabel.font = .menuFont(ofSize: NSFont.systemFontSize)
        detailLabel.alignment = .right
        detailLabel.lineBreakMode = .byTruncatingMiddle
        detailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        if selection == nil {
            // Round up so pixel alignment cannot truncate short setting values.
            detailLabel.widthAnchor.constraint(
                greaterThanOrEqualToConstant: ceil(detailLabel.intrinsicContentSize.width)
            ).isActive = true
        }

        chevron.identifier = NSUserInterfaceItemIdentifier(
            chevronIdentifier ?? (selection == nil ? "setting-chevron" : "configuration-chevron")
        )
        chevron.image = NSImage(
            systemSymbolName: "chevron.right",
            accessibilityDescription: nil
        )
        chevron.isHidden = !showsChevron
        chevron.translatesAutoresizingMaskIntoConstraints = false

        addSubview(checkmark)
        addSubview(titleLabel)
        addSubview(detailLabel)
        addSubview(chevron)

        NSLayoutConstraint.activate([
            checkmark.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            checkmark.centerYAnchor.constraint(equalTo: centerYAnchor),
            checkmark.widthAnchor.constraint(equalToConstant: 12),
            checkmark.heightAnchor.constraint(equalToConstant: 12),
            selection == nil
                ? titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12)
                : titleLabel.leadingAnchor.constraint(equalTo: checkmark.trailingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            detailLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: titleLabel.trailingAnchor,
                constant: 12
            ),
            detailLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            showsChevron
                ? detailLabel.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -8)
                : detailLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 8),
            chevron.heightAnchor.constraint(equalToConstant: 12),
        ])

        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard isMenuHighlighted else {
            return
        }

        NSColor.selectedContentBackgroundColor.setFill()
        NSBezierPath(
            roundedRect: bounds.insetBy(dx: 5, dy: 1),
            xRadius: 5,
            yRadius: 5
        ).fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func setMenuHighlighted(_ highlighted: Bool) {
        guard isMenuHighlighted != highlighted else {
            return
        }
        isMenuHighlighted = highlighted
        updateAppearance()
        needsDisplay = true
    }

    func addConfigurationActions(
        target: AnyObject,
        selection: [String: String],
        destinationMenu: NSMenu,
        selectSchemeAction: Selector,
        showDestinationMenuAction: Selector
    ) {
        let schemeButton = ConfigurationActionButton(
            title: "",
            target: target,
            action: selectSchemeAction
        )
        schemeButton.identifier = NSUserInterfaceItemIdentifier("scheme-selection-button")
        schemeButton.representedSelection = selection
        schemeButton.isBordered = false
        schemeButton.isTransparent = true
        schemeButton.focusRingType = .none
        schemeButton.toolTip = "Use \(titleLabel.stringValue) for Play"
        schemeButton.setAccessibilityLabel("Use \(titleLabel.stringValue) for Play")
        schemeButton.translatesAutoresizingMaskIntoConstraints = false

        let destinationButton = NSButton(
            title: "",
            target: target,
            action: showDestinationMenuAction
        )
        destinationButton.identifier = NSUserInterfaceItemIdentifier("destination-menu-button")
        destinationButton.menu = destinationMenu
        destinationButton.isBordered = false
        destinationButton.isTransparent = true
        destinationButton.focusRingType = .none
        destinationButton.toolTip = "Choose device for \(titleLabel.stringValue)"
        destinationButton.setAccessibilityLabel(
            "Choose device for \(titleLabel.stringValue), \(detailLabel.stringValue)"
        )
        destinationButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(schemeButton)
        addSubview(destinationButton)
        NSLayoutConstraint.activate([
            schemeButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            schemeButton.trailingAnchor.constraint(equalTo: detailLabel.leadingAnchor),
            schemeButton.topAnchor.constraint(equalTo: topAnchor),
            schemeButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            destinationButton.leadingAnchor.constraint(equalTo: detailLabel.leadingAnchor),
            destinationButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            destinationButton.topAnchor.constraint(equalTo: topAnchor),
            destinationButton.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func updateAppearance() {
        let primaryColor: NSColor = isMenuHighlighted
            ? .selectedMenuItemTextColor
            : .labelColor
        let secondaryColor: NSColor = isMenuHighlighted
            ? .selectedMenuItemTextColor
            : .secondaryLabelColor
        titleLabel.textColor = primaryColor
        detailLabel.textColor = secondaryColor
        checkmark.contentTintColor = primaryColor
        chevron.contentTintColor = secondaryColor
    }
}

private final class StatusDeviceImageView: NSImageView {
    // Keep symbol-specific optical insets from expanding into the loading dots.
    override var alignmentRectInsets: NSEdgeInsets {
        NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }
}

private final class StatusItemView: NSView {
    let iconImageView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let destinationImageView = StatusDeviceImageView()
    private let contentStack = NSStackView()
    private let dotsView: NSStackView
    private let dots: [NSView]
    private var dotsCenterConstraint: NSLayoutConstraint?

    override init(frame frameRect: NSRect) {
        dots = (0..<3).map { index in
            let dot = NSView()
            dot.identifier = NSUserInterfaceItemIdentifier("running-dot-\(index)")
            dot.wantsLayer = true
            dot.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                dot.widthAnchor.constraint(equalToConstant: 2),
                dot.heightAnchor.constraint(equalToConstant: 2),
            ])
            dot.layer?.cornerRadius = 1
            return dot
        }
        dotsView = NSStackView(views: dots)
        super.init(frame: frameRect)
        identifier = NSUserInterfaceItemIdentifier("status-content")
        translatesAutoresizingMaskIntoConstraints = false

        contentStack.orientation = .horizontal
        contentStack.alignment = .centerY
        contentStack.spacing = 4
        contentStack.detachesHiddenViews = true
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStack)

        iconImageView.identifier = NSUserInterfaceItemIdentifier("xplay-status-icon")
        iconImageView.imageScaling = .scaleProportionallyDown
        iconImageView.contentTintColor = .labelColor
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(iconImageView)

        nameLabel.identifier = NSUserInterfaceItemIdentifier("status-project-name")
        nameLabel.font = .menuBarFont(ofSize: 13)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(nameLabel)

        destinationImageView.identifier = NSUserInterfaceItemIdentifier("destination-status-icon")
        destinationImageView.imageScaling = .scaleProportionallyDown
        destinationImageView.contentTintColor = .labelColor
        destinationImageView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(destinationImageView)

        dotsView.identifier = NSUserInterfaceItemIdentifier("running-dots")
        dotsView.orientation = .horizontal
        dotsView.alignment = .centerY
        dotsView.spacing = 2
        dotsView.translatesAutoresizingMaskIntoConstraints = false
        dotsView.isHidden = true
        addSubview(dotsView)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 22),
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentStack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -1),
            iconImageView.widthAnchor.constraint(equalToConstant: 21),
            iconImageView.heightAnchor.constraint(equalToConstant: 18),
            nameLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 160),
            destinationImageView.widthAnchor.constraint(equalToConstant: 16),
            destinationImageView.heightAnchor.constraint(equalToConstant: 14),
            dotsView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        updateDotColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateDotColors()
    }

    var showsOnlyLogo: Bool { !iconImageView.isHidden }

    func configure(content: AppSettings.MenuBarContent, projectName: String?, destination: XcodeDestination?) {
        nameLabel.stringValue = projectName ?? ""
        nameLabel.isHidden = projectName == nil || (content != .name && content != .nameAndTarget)
        destinationImageView.isHidden = destination == nil || (content != .target && content != .nameAndTarget)
        iconImageView.isHidden = !(nameLabel.isHidden && destinationImageView.isHidden)
        setDestination(destination)

        dotsCenterConstraint?.isActive = false
        if !destinationImageView.isHidden {
            dotsCenterConstraint = dotsView.centerXAnchor.constraint(equalTo: contentStack.trailingAnchor, constant: -8)
        } else {
            dotsCenterConstraint = dotsView.centerXAnchor.constraint(equalTo: contentStack.centerXAnchor)
        }
        dotsCenterConstraint?.isActive = true
    }

    private func setDestination(_ destination: XcodeDestination?) {
        destinationImageView.setAccessibilityLabel(destination?.displayName)
        guard let destination else {
            destinationImageView.image = nil
            return
        }
        let symbol: String
        let description: String
        switch destination.platform {
        case .macOS:
            symbol = "desktopcomputer"
            description = "Mac"
        case .iOSSimulator where destination.name.localizedCaseInsensitiveContains("iPad"):
            symbol = "ipad"
            description = "iPad"
        case .iOSSimulator where destination.name.localizedCaseInsensitiveContains("iPhone"):
            symbol = "iphone"
            description = "iPhone"
        case .iOSSimulator:
            symbol = "ipad.and.iphone"
            description = "iOS Simulator"
        }
        destinationImageView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
    }

    func startAnimating() {
        dotsView.isHidden = false
        for (index, dot) in dots.enumerated() {
            guard let layer = dot.layer else { continue }
            let animation = CAKeyframeAnimation(keyPath: "opacity")
            animation.values = [0.25, 1, 0.25]
            animation.keyTimes = [0, 0.5, 1]
            animation.duration = 0.9
            animation.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil)
                + (Double(index) * 0.18)
            animation.fillMode = .both
            animation.repeatCount = .infinity
            layer.add(animation, forKey: "pulse")
        }
    }

    func stopAnimating() {
        for dot in dots {
            dot.layer?.removeAnimation(forKey: "pulse")
        }
        dotsView.isHidden = true
    }

    private func updateDotColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let color = NSColor.labelColor.cgColor
            dots.forEach { $0.layer?.backgroundColor = color }
        }
    }
}

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
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
    private let statusItemView: StatusItemView
    private let projectCatalog: ProjectCatalog?
    private let appSettings: AppSettings
    private let onEditProjects: (() -> Void)?
    private let onCatalogChange: (() -> Void)?
    private let confirmMacroAcceptance: () -> Bool
    private let cacheDirectory: URL
    private let makeLauncher: (XcodeProjectLaunchPlan) -> any ProjectLaunching
    private let presentLaunchFailures: ([LaunchFailure]) -> Void
    private let appVersion: String?
    private let openExternalURL: (URL) -> Void
    private let presentDestinationMenu: (NSMenu, NSPoint) -> Void
    private var activeLauncher: (any ProjectLaunching)?
    private var activeLaunchID: UUID?
    private var isRunning = false
    private var activeLaunchPlan: XcodeProjectLaunchPlan?
    private weak var playMenuItem: NSMenuItem?
    private weak var playMenuButton: NSButton?
    private weak var playMenuSpinner: NSProgressIndicator?
    private weak var stopMenuButton: NSButton?

    private(set) lazy var contextMenu = makeContextMenu()

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        menu.addItem(makeSectionHeaderItem(
            title: projectCatalog?.selectedProject?.name ?? "No project selected"
        ))

        if let project = projectCatalog?.selectedProject {
            let configurations = project.enabledConfigurations
            for configuration in configurations {
                menu.addItem(
                    makeConfigurationItem(
                        configuration,
                        projectURL: project.url,
                        isSelectedForPlay: configuration.scheme
                            == project.selectedLaunchConfigurationScheme
                    )
                )
            }
        }
        menu.addItem(makePlayItem())
        menu.addItem(.separator())

        menu.addItem(makeSectionHeaderItem(title: "Projects", showsEditButton: true))

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

        menu.addItem(makeSectionHeaderItem(title: "Settings"))

        menu.addItem(makeChoiceItem(
            title: "Menu Bar Icon",
            labels: ["XPlay", "Name + Target", "Name", "Target"],
            selectedIndex: AppSettings.MenuBarContent.allCases.firstIndex(of: appSettings.menuBarContent)!,
            action: #selector(setMenuBarContent(_:))
        ))
        menu.addItem(makeChoiceItem(
            title: "Left Click", labels: ["Play", "Menu"],
            selectedIndex: appSettings.leftClickAction == .play ? 0 : 1,
            action: #selector(setLeftClickAction(_:))
        ))
        menu.addItem(makeChoiceItem(
            title: "Right Click", labels: ["Play", "Menu"],
            selectedIndex: appSettings.rightClickAction == .play ? 0 : 1,
            action: #selector(setRightClickAction(_:))
        ))
        menu.addItem(makeMacroAcceptanceItem())
        menu.addItem(.separator())

        menu.addItem(makeSectionHeaderItem(title: "About"))
        menu.addItem(makeAboutItem())
        menu.addItem(makeExternalLinkItem(
            title: "Report a Problem…",
            url: URL(string: "https://github.com/mobilepur/xplay/issues/new")!
        ))
        menu.addItem(.separator())

        menu.addItem(makeQuitItem())

        return menu
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        for menuItem in menu.items {
            guard let row = menuItem.view as? MenuDetailItemView else {
                continue
            }
            row.setMenuHighlighted(menuItem === item)
        }
    }

    private func makeConfigurationItem(
        _ configuration: LaunchConfiguration,
        projectURL: URL,
        isSelectedForPlay: Bool
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
            title: configuration.scheme,
            action: nil,
            keyEquivalent: ""
        )
        item.isEnabled = true
        item.setAccessibilityLabel("\(configuration.scheme), \(destinationTitle)")
        item.state = isSelectedForPlay ? .on : .off
        let destinationMenu = NSMenu(title: configuration.scheme)
        destinationMenu.autoenablesItems = false

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
            destinationMenu.addItem(unavailableItem)
        }

        if configuration.availableDestinations.isEmpty {
            let placeholder = NSMenuItem(
                title: "No destinations available",
                action: nil,
                keyEquivalent: ""
            )
            placeholder.isEnabled = false
            destinationMenu.addItem(placeholder)
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
                destinationMenu.addItem(destinationItem)
            }
        }
        item.view = makeConfigurationRow(
            scheme: configuration.scheme,
            destination: destinationTitle,
            isSelectedForPlay: isSelectedForPlay,
            projectURL: projectURL,
            destinationMenu: destinationMenu
        )
        return item
    }

    private func makeConfigurationRow(
        scheme: String,
        destination: String,
        isSelectedForPlay: Bool,
        projectURL: URL,
        destinationMenu: NSMenu
    ) -> NSView {
        let row = MenuDetailItemView(
            title: scheme,
            detail: destination,
            selection: isSelectedForPlay
        )
        row.addConfigurationActions(
            target: self,
            selection: [
                "projectPath": projectURL.path,
                "scheme": scheme,
            ],
            destinationMenu: destinationMenu,
            selectSchemeAction: #selector(selectLaunchConfiguration(_:)),
            showDestinationMenuAction: #selector(showDestinationMenu(_:))
        )
        return row
    }

    private func makePlayItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Run Project", action: #selector(playFromMenu), keyEquivalent: "")
        item.target = self
        let row = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 54))
        row.autoresizingMask = [.width]
        let playButton = NSButton(title: "Run Project", target: self, action: #selector(playFromMenu))
        playButton.identifier = NSUserInterfaceItemIdentifier("run-project-button")
        playButton.bezelStyle = .rounded
        playButton.controlSize = .large
        playButton.font = .systemFont(ofSize: 16, weight: .medium)
        playButton.bezelColor = .controlAccentColor
        playButton.image = menuBarImage(description: "XPlay")
        playButton.imagePosition = .imageLeading
        playButton.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let spinner = NSProgressIndicator()
        spinner.identifier = NSUserInterfaceItemIdentifier("run-project-spinner")
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.isDisplayedWhenStopped = false
        spinner.isHidden = true
        spinner.setAccessibilityElement(false)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        playButton.addSubview(spinner)

        let stopButton = NSButton(title: "", target: self, action: #selector(stopFromMenu))
        stopButton.identifier = NSUserInterfaceItemIdentifier("stop-project-button")
        stopButton.bezelStyle = .rounded
        stopButton.controlSize = .large
        stopButton.image = NSImage(
            systemSymbolName: "stop.fill",
            accessibilityDescription: "Stop"
        )
        stopButton.imagePosition = .imageOnly
        stopButton.setAccessibilityLabel("Stop")
        stopButton.setContentHuggingPriority(.required, for: .horizontal)
        stopButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        let buttons = NSStackView(views: [playButton, stopButton])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.distribution = .fill
        buttons.spacing = 8
        buttons.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(buttons)
        NSLayoutConstraint.activate([
            buttons.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 12),
            buttons.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -12),
            buttons.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            buttons.heightAnchor.constraint(equalToConstant: 38),
            stopButton.widthAnchor.constraint(equalToConstant: 44),
            spinner.trailingAnchor.constraint(equalTo: playButton.trailingAnchor, constant: -14),
            spinner.centerYAnchor.constraint(equalTo: playButton.centerYAnchor),
            spinner.widthAnchor.constraint(equalToConstant: 14),
            spinner.heightAnchor.constraint(equalToConstant: 14),
        ])
        item.view = row
        playMenuItem = item
        playMenuButton = playButton
        playMenuSpinner = spinner
        stopMenuButton = stopButton
        updateLaunchButtons()
        return item
    }

    private func updateLaunchButtons() {
        let canStart = !isRunning && projectCatalog?.selectedProject?
            .selectedLaunchConfiguration?.isSelectedDestinationAvailable == true
        let canStop = isRunning && activeLauncher != nil
        playMenuItem?.isEnabled = canStart || canStop
        playMenuButton?.isEnabled = canStart
        stopMenuButton?.isEnabled = canStop
        playMenuSpinner?.isHidden = !isRunning
        if isRunning {
            playMenuSpinner?.startAnimation(nil)
        } else {
            playMenuSpinner?.stopAnimation(nil)
        }
        playMenuButton?.toolTip = projectCatalog?.selectedProject?.selectedLaunchConfiguration.map {
            "Build and launch \($0.scheme)"
        } ?? "Select a scheme and destination to play"
        stopMenuButton?.toolTip = activeLaunchPlan.map {
            "Stop building and launching \($0.scheme)"
        } ?? "No launch in progress"
    }

    private func makeChoiceItem(title: String, labels: [String], selectedIndex: Int, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        submenu.autoenablesItems = false
        for (index, label) in labels.enumerated() {
            let choice = NSMenuItem(title: label, action: action, keyEquivalent: "")
            choice.target = self
            choice.tag = index
            choice.state = index == selectedIndex ? .on : .off
            choice.isEnabled = true
            submenu.addItem(choice)
        }
        item.submenu = submenu
        item.view = MenuDetailItemView(title: title, detail: labels[selectedIndex])
        item.setAccessibilityLabel("\(title), \(labels[selectedIndex])")
        item.isEnabled = true
        if title == "Left Click" || title == "Right Click" {
            item.toolTip = "One click runs the project; the other opens the menu. Changing either action swaps both."
        }
        return item
    }

    @objc private func playFromMenu() {
        contextMenu.cancelTracking()
        startProject()
    }

    @objc private func stopFromMenu() {
        contextMenu.cancelTracking()
        stopProject()
    }

    @objc private func setMenuBarContent(_ item: NSMenuItem) {
        guard AppSettings.MenuBarContent.allCases.indices.contains(item.tag) else { return }
        appSettings.setMenuBarContent(AppSettings.MenuBarContent.allCases[item.tag])
        finishSettingsChange()
    }

    @objc private func setLeftClickAction(_ item: NSMenuItem) {
        appSettings.setLeftClickAction(item.tag == 0 ? .play : .menu)
        finishSettingsChange()
    }

    @objc private func setRightClickAction(_ item: NSMenuItem) {
        appSettings.setRightClickAction(item.tag == 0 ? .play : .menu)
        finishSettingsChange()
    }

    private func finishSettingsChange() {
        contextMenu = makeContextMenu()
        refreshConfiguration()
    }

    private func makeQuitItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: "Quit",
            action: #selector(quitApplication),
            keyEquivalent: "q"
        )
        item.target = self
        item.isEnabled = true
        item.view = MenuDetailItemView(
            title: "Quit",
            detail: "⌘Q",
            showsChevron: false
        )
        item.setAccessibilityLabel("Quit, Command Q")
        return item
    }

    private func makeAboutItem() -> NSMenuItem {
        let displayedVersion = appVersion ?? "Development"
        let releasesURL: URL
        if let appVersion {
            releasesURL = URL(
                string: "https://github.com/mobilepur/xplay/releases/tag/v\(appVersion)"
            )!
        } else {
            releasesURL = URL(string: "https://github.com/mobilepur/xplay/releases")!
        }
        return makeExternalLinkItem(
            title: "XPlay",
            detail: displayedVersion,
            url: releasesURL,
            toolTip: appVersion.map { "View GitHub release notes for version \($0)" }
                ?? "View GitHub releases"
        )
    }

    private func makeExternalLinkItem(
        title: String,
        detail: String = "",
        url: URL,
        toolTip: String? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: #selector(openExternalLink(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.representedObject = url
        item.isEnabled = true
        item.toolTip = toolTip
        item.view = MenuDetailItemView(
            title: title,
            detail: detail,
            chevronIdentifier: "navigation-chevron"
        )
        item.setAccessibilityLabel(
            detail.isEmpty ? title : "\(title), \(detail)"
        )
        return item
    }

    private func makeSectionHeaderItem(title: String, showsEditButton: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = showsEditButton && onEditProjects != nil

        let headerView = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 28))
        headerView.autoresizingMask = [.width]

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 12),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
        ])

        if showsEditButton {
            let editButton = NSButton(title: "Edit", target: self, action: #selector(editProjects))
            editButton.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            editButton.isBordered = false
            editButton.isEnabled = onEditProjects != nil
            editButton.translatesAutoresizingMaskIntoConstraints = false
            headerView.addSubview(editButton)

            NSLayoutConstraint.activate([
                editButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -8),
                editButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
                titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: editButton.leadingAnchor, constant: -8),
            ])
        } else {
            titleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: headerView.trailingAnchor, constant: -12
            ).isActive = true
        }

        item.view = headerView
        return item
    }

    private func makeMacroAcceptanceItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Accept Macros", action: nil, keyEquivalent: "")
        item.isEnabled = true

        let rowView = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 32))
        rowView.autoresizingMask = [.width]

        let label = NSTextField(labelWithString: "Accept Macros")
        label.font = .menuFont(ofSize: NSFont.systemFontSize)
        label.translatesAutoresizingMaskIntoConstraints = false

        let toggle = NSSwitch(frame: .zero)
        toggle.controlSize = .small
        toggle.state = appSettings.acceptsMacros ? .on : .off
        toggle.target = self
        toggle.action = #selector(setMacroAcceptance(_:))
        toggle.toolTip = Self.macroWarningText
        toggle.setAccessibilityLabel("Accept Macros")
        toggle.translatesAutoresizingMaskIntoConstraints = false

        rowView.addSubview(label)
        rowView.addSubview(toggle)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: rowView.leadingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),
            toggle.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 12),
            toggle.trailingAnchor.constraint(equalTo: rowView.trailingAnchor, constant: -12),
            toggle.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),
        ])

        item.view = rowView
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
        presentLaunchFailures: (([LaunchFailure]) -> Void)? = nil,
        appVersion: String? = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String,
        openExternalURL: @escaping (URL) -> Void = { url in
            NSWorkspace.shared.open(url)
        },
        presentDestinationMenu: @escaping (NSMenu, NSPoint) -> Void = { menu, point in
            menu.popUp(positioning: nil, at: point, in: nil)
        }
    ) {
        self.projectCatalog = projectCatalog
        self.appSettings = appSettings ?? AppSettings()
        self.onEditProjects = onEditProjects
        self.onCatalogChange = onCatalogChange
        self.confirmMacroAcceptance = confirmMacroAcceptance ?? Self.presentMacroWarning
        self.cacheDirectory = cacheDirectory
        self.makeLauncher = makeLauncher
        self.presentLaunchFailures = presentLaunchFailures ?? Self.presentDefaultLaunchFailures
        self.appVersion = appVersion
        self.openExternalURL = openExternalURL
        self.presentDestinationMenu = presentDestinationMenu
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItemView = StatusItemView()

        super.init()

        guard let button = statusItem.button else {
            return
        }

        button.target = self
        button.action = #selector(handleStatusItemClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        button.addSubview(statusItemView)

        NSLayoutConstraint.activate([
            statusItemView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            statusItemView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
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

    static func interaction(
        for eventType: NSEvent.EventType,
        leftClickAction: AppSettings.ClickAction = .play,
        rightClickAction: AppSettings.ClickAction = .menu
    ) -> Interaction? {
        switch eventType {
        case .leftMouseUp:
            return leftClickAction == .play ? .startProject : .showContextMenu
        case .rightMouseUp:
            return rightClickAction == .play ? .startProject : .showContextMenu
        default:
            return nil
        }
    }

    @objc
    private func handleStatusItemClick() {
        guard
            let eventType = NSApp.currentEvent?.type,
            let interaction = Self.interaction(
                for: eventType,
                leftClickAction: appSettings.leftClickAction,
                rightClickAction: appSettings.rightClickAction
            )
        else {
            return
        }

        perform(interaction)
    }

    func perform(_ interaction: Interaction) {
        switch interaction {
        case .startProject:
            if isRunning {
                stopProject()
            } else {
                startProject()
            }
        case .showContextMenu:
            showContextMenu()
        }
    }

    private func startProject() {
        guard
            !isRunning,
            let project = projectCatalog?.selectedProject,
            let configuration = project.selectedLaunchConfiguration,
            let plan = XcodeProjectLaunchPlan.make(
                for: project,
                configuration: configuration,
                cacheDirectory: cacheDirectory,
                acceptsMacros: appSettings.acceptsMacros
            )
        else {
            return
        }

        let launchID = UUID()
        activeLaunchID = launchID
        activeLaunchPlan = plan
        setRunning(true)
        launchNext(in: [plan], at: 0, failures: [], launchID: launchID)
    }

    private func launchNext(
        in plans: [XcodeProjectLaunchPlan],
        at index: Int,
        failures: [LaunchFailure],
        launchID: UUID
    ) {
        guard activeLaunchID == launchID else {
            return
        }
        guard plans.indices.contains(index) else {
            activeLauncher = nil
            activeLaunchID = nil
            activeLaunchPlan = nil
            setRunning(false)
            if !failures.isEmpty {
                presentLaunchFailures(failures)
            }
            return
        }

        let plan = plans[index]
        let launcher = makeLauncher(plan)
        activeLauncher = launcher
        updateLaunchButtons()
        setRunningProgress(plan: plan, index: index, total: plans.count)
        launcher.launch { [weak self] result in
            Task { @MainActor in
                guard let self, self.activeLaunchID == launchID else {
                    return
                }
                var updatedFailures = failures
                if case let .failure(error) = result {
                    updatedFailures.append(LaunchFailure(plan: plan, error: error))
                }
                self.launchNext(
                    in: plans,
                    at: index + 1,
                    failures: updatedFailures,
                    launchID: launchID
                )
            }
        }
    }

    private func stopProject() {
        guard isRunning else {
            return
        }
        let launcher = activeLauncher
        activeLaunchID = nil
        activeLauncher = nil
        activeLaunchPlan = nil
        setRunning(false)
        launcher?.cancel()
    }

    private func showContextMenu() {
        contextMenu = makeContextMenu()
        statusItem.menu = contextMenu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc
    private func openExternalLink(_ item: NSMenuItem) {
        guard let url = item.representedObject as? URL else { return }
        contextMenu.cancelTracking()
        openExternalURL(url)
    }

    @objc
    private func quitApplication() {
        NSApp.terminate(nil)
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
        projectCatalog?.selectLaunchConfiguration(
            scheme: scheme,
            forProjectAt: projectIndex
        )
        finishCatalogSelection()
    }

    @objc
    private func selectLaunchConfiguration(_ button: ConfigurationActionButton) {
        contextMenu.cancelTracking()
        applyLaunchConfigurationSelection(button.representedSelection)
    }

    private func applyLaunchConfigurationSelection(_ selection: [String: String]?) {
        guard
            let selection,
            let projectPath = selection["projectPath"],
            let scheme = selection["scheme"],
            let projectIndex = projectCatalog?.projects.firstIndex(where: {
                $0.url.path == projectPath
            })
        else {
            return
        }

        projectCatalog?.selectLaunchConfiguration(
            scheme: scheme,
            forProjectAt: projectIndex
        )
        finishCatalogSelection()
    }

    @objc
    private func showDestinationMenu(_ button: NSButton) {
        guard let menu = button.menu else {
            return
        }
        let windowPoint = button.convert(
            NSPoint(x: button.bounds.maxX + 4, y: button.bounds.maxY),
            to: nil
        )
        let screenPoint = button.window?.convertPoint(toScreen: windowPoint) ?? .zero
        contextMenu.cancelTracking()
        presentDestinationMenu(menu, screenPoint)
    }

    private func finishCatalogSelection() {
        onCatalogChange?()
        contextMenu = makeContextMenu()
        refreshConfiguration()
    }

    @objc
    private func setMacroAcceptance(_ toggle: NSSwitch) {
        if toggle.state == .on {
            guard confirmMacroAcceptance() else {
                toggle.state = .off
                return
            }
            appSettings.setAcceptsMacros(true)
        } else {
            appSettings.setAcceptsMacros(false)
        }
        contextMenu = makeContextMenu()
    }

    private func setRunning(_ running: Bool) {
        isRunning = running
        if running {
            statusItemView.startAnimating()
        } else {
            statusItemView.stopAnimating()
        }
        refreshConfiguration()
    }

    private func setRunningProgress(
        plan: XcodeProjectLaunchPlan,
        index: Int,
        total: Int
    ) {
        guard isRunning, let button = statusItem.button else {
            return
        }
        if total == 1 {
            button.setAccessibilityLabel(appSettings.leftClickAction == .menu ? "Open XPlay menu" : "Starting \(plan.scheme)")
            button.toolTip = "Building and launching \(plan.scheme)…"
        } else {
            let position = "\(index + 1) of \(total)"
            button.setAccessibilityLabel("Starting \(plan.scheme) (\(position))")
            button.toolTip = "Building and launching \(plan.scheme) (\(position))…"
        }
    }

    func refreshConfiguration() {
        guard let button = statusItem.button else { return }
        let project = projectCatalog?.selectedProject
        let configuration = project?.selectedLaunchConfiguration
        let destination = activeLaunchPlan?.destination ?? configuration?.selectedDestination
        let canStart = configuration?.isSelectedDestinationAvailable == true
        let description: String
        if let plan = activeLaunchPlan {
            description = "Building and launching \(plan.scheme)…"
        } else if canStart {
            description = "Start project"
        } else if configuration != nil {
            description = "Choose a destination for the selected scheme"
        } else {
            description = "No project scheme selected"
        }
        button.image = nil
        statusItemView.iconImageView.image = menuBarImage(description: "XPlay")
        statusItemView.configure(
            content: appSettings.menuBarContent,
            projectName: activeLaunchPlan?.productName ?? project?.name,
            destination: destination
        )
        statusItem.length = statusItemView.showsOnlyLogo
            ? NSStatusItem.squareLength
            : max(NSStatusBar.system.thickness, statusItemView.fittingSize.width + 8)
        let menuHint = appSettings.leftClickAction == .menu ? "Left-click for menu" : "Right-click for menu"
        if appSettings.leftClickAction == .menu {
            button.setAccessibilityLabel("Open XPlay menu")
        } else if let plan = activeLaunchPlan {
            button.setAccessibilityLabel("Starting \(plan.scheme)")
        } else {
            button.setAccessibilityLabel(canStart ? "Start project" : "\(description). \(menuHint)")
        }
        button.setAccessibilityHelp([destination?.displayName, menuHint].compactMap { $0 }.joined(separator: ". "))
        button.toolTip = canStart && appSettings.leftClickAction == .play
            ? description : "\(description) · \(menuHint)"
        updateLaunchButtons()
    }

    private func menuBarImage(description: String) -> NSImage? {
        let image = NSImage(named: "XPlayIcon")
        image?.size = NSSize(width: 21, height: 18)
        image?.accessibilityDescription = description
        image?.isTemplate = true
        return image
    }
}
