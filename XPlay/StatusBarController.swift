import AppKit
import SwiftUI

@MainActor
private final class MenuSwitchState: ObservableObject {
    @Published var isOn = false
    @Published var isEnabled = true
}

private struct MenuSwitchContent: View {
    @ObservedObject var model: MenuSwitchState
    let title: String
    let setOn: (Bool) -> Void

    var body: some View {
        Toggle(title, isOn: Binding(get: { model.isOn }, set: setOn))
            .labelsHidden()
            .toggleStyle(MenuSwitchStyle())
            .disabled(!model.isEnabled)
            .fixedSize()
    }
}

private struct MenuSwitchStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.12)) {
                configuration.isOn.toggle()
            }
        } label: {
            Capsule()
                .fill(configuration.isOn ? Color(nsColor: .systemBlue) : Color.primary.opacity(0.15))
                .frame(width: 44, height: 20)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule().fill(.white)
                        .frame(width: 26, height: 16)
                        .padding(.horizontal, 2)
                }
                .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .highPriorityGesture(DragGesture(minimumDistance: 4).onEnded { value in
            guard isEnabled else { return }
            withAnimation(.easeInOut(duration: 0.12)) {
                configuration.isOn = value.location.x >= 22
            }
        })
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .toggleStyle(.switch)
        }
    }
}

@MainActor
final class MenuTintedSwitch: NSControl {
    private let model = MenuSwitchState()
    private var hostingView: NSHostingView<MenuSwitchContent>!

    var state: NSControl.StateValue {
        get { model.isOn ? .on : .off }
        set { model.isOn = newValue == .on }
    }

    override var isEnabled: Bool {
        didSet { model.isEnabled = isEnabled }
    }

    init(title: String) {
        super.init(frame: .zero)
        // NSSwitch has no public tint API. Use an accessible SwiftUI toggle
        // with explicit colors that remain visible in a non-key menu window.
        hostingView = NSHostingView(rootView: MenuSwitchContent(model: model, title: title) { [weak self] isOn in
            guard let self, self.isEnabled else { return }
            self.state = isOn ? .on : .off
            self.sendAction(self.action, to: self.target)
        })
        hostingView.frame = bounds
        hostingView.autoresizingMask = [.width, .height]
        addSubview(hostingView)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize { hostingView.fittingSize }

    override func performClick(_ sender: Any?) {
        guard isEnabled else { return }
        state = state == .on ? .off : .on
        sendAction(action, to: target)
    }
}

@MainActor
private final class MenuRunButtonCell: NSButtonCell {
    override var interiorBackgroundStyle: NSView.BackgroundStyle {
        isEnabled ? .emphasized : super.interiorBackgroundStyle
    }

    override func drawBezel(withFrame frame: NSRect, in controlView: NSView) {
        guard isEnabled else {
            super.drawBezel(withFrame: frame, in: controlView)
            return
        }
        let content = drawingRect(forBounds: frame)
        let bezel = NSRect(x: frame.minX, y: content.minY, width: frame.width, height: content.height)
        let radius: CGFloat
        if #available(macOS 26.0, *) { radius = bezel.height / 2 } else { radius = 6 }
        let color = isHighlighted ? NSColor.systemBlue.blended(withFraction: 0.18, of: .black)! : .systemBlue
        color.setFill()
        NSBezierPath(roundedRect: bezel, xRadius: radius, yRadius: radius).fill()
    }

    override func drawTitle(_ title: NSAttributedString, withFrame frame: NSRect, in controlView: NSView) -> NSRect {
        guard isEnabled else { return super.drawTitle(title, withFrame: frame, in: controlView) }
        let text = NSMutableAttributedString(attributedString: title)
        text.addAttribute(.foregroundColor, value: NSColor.white, range: NSRange(location: 0, length: text.length))
        return super.drawTitle(text, withFrame: frame, in: controlView)
    }

    override func drawImage(_ image: NSImage, withFrame frame: NSRect, in controlView: NSView) {
        guard isEnabled, image.isTemplate else {
            super.drawImage(image, withFrame: frame, in: controlView)
            return
        }
        let tinted = NSImage(size: image.size, flipped: false) { bounds in
            image.draw(in: bounds)
            NSColor.white.setFill()
            bounds.fill(using: .sourceIn)
            return true
        }
        super.drawImage(tinted, withFrame: frame, in: controlView)
    }
}

@MainActor
private final class ConfigurationActionButton: NSButton {
    var representedSelection: [String: String]?
}

@MainActor
private final class BranchSelectionButton: NSButton {
    var copy: GitWorkingCopy

    init(copy: GitWorkingCopy, target: AnyObject, action: Selector) {
        self.copy = copy
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 44))
        title = ""
        isTransparent = true
        self.target = target
        self.action = action
        identifier = NSUserInterfaceItemIdentifier("branch-selection-button")
        isBordered = false
        alignment = .left
        imagePosition = .imageLeading
        imageHugsTitle = true
        autoresizingMask = [.width]
        setButtonType(.momentaryPushIn)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(copy: GitWorkingCopy, subtitle: String?, selected: Bool, enabled: Bool) {
        self.copy = copy
        isEnabled = enabled
        if let row = superview as? MenuDetailItemView {
            row.updateSelection(title: copy.displayName, subtitle: subtitle, selected: selected, enabled: enabled)
            frame = row.bounds
        }
        setAccessibilityLabel([copy.displayName, subtitle].compactMap { $0 }.joined(separator: ", "))
        setAccessibilityValue(selected ? 1 : 0)
    }
}

@MainActor
private final class ExternalLinkButton: NSButton {
    var externalURL: URL?
}

@MainActor
private final class CompactStopButton: NSButton {
    override var intrinsicContentSize: NSSize {
        NSSize(width: 44, height: super.intrinsicContentSize.height)
    }
}

@MainActor
private final class MenuDetailItemView: NSView {
    private let titleLabel: NSTextField
    private let detailLabel: NSTextField
    private let checkmark: NSImageView
    private let chevron: NSImageView
    private var isMenuHighlighted = false
    private var selectionEnabled = true
    private var isSelected = false

    init(
        title: String,
        detail: String,
        selection: Bool? = nil,
        chevronIdentifier: String? = nil,
        showsChevron: Bool = true,
        trailingAccessoryWidth: CGFloat = 0
    ) {
        titleLabel = NSTextField(labelWithString: title)
        detailLabel = NSTextField(labelWithString: detail)
        checkmark = NSImageView()
        chevron = NSImageView()

        super.init(frame: NSRect(x: 0, y: 0, width: 320 + trailingAccessoryWidth, height: 28))

        isSelected = selection == true
        autoresizingMask = [.width]

        checkmark.identifier = NSUserInterfaceItemIdentifier("configuration-checkmark")
        checkmark.image = selectionImage(selected: selection == true)
        checkmark.isHidden = selection == nil
        checkmark.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.identifier = NSUserInterfaceItemIdentifier("selection-title")
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
            checkmark.widthAnchor.constraint(equalToConstant: 14),
            checkmark.heightAnchor.constraint(equalToConstant: 14),
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
                : detailLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12 - trailingAccessoryWidth),
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
        destinationButton.title = "Change…"
        destinationButton.bezelStyle = .rounded
        destinationButton.controlSize = .small
        destinationButton.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
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
            schemeButton.trailingAnchor.constraint(equalTo: destinationButton.leadingAnchor, constant: -4),
            schemeButton.topAnchor.constraint(equalTo: topAnchor),
            schemeButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            destinationButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            destinationButton.widthAnchor.constraint(equalToConstant: 70),
            destinationButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            destinationButton.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    private func selectionImage(selected: Bool) -> NSImage? {
        let image = NSImage(systemSymbolName: selected ? "largecircle.fill.circle" : "circle",
                            accessibilityDescription: nil)
        image?.size = NSSize(width: 14, height: 14)
        return image
    }

    func updateSelection(title: String, subtitle: String?, selected: Bool, enabled: Bool) {
        selectionEnabled = enabled
        isSelected = selected
        checkmark.image = selectionImage(selected: selected)
        checkmark.isHidden = false
        let text = NSMutableAttributedString(string: title, attributes: [
            .font: NSFont.menuFont(ofSize: NSFont.systemFontSize),
        ])
        if let subtitle {
            text.append(NSAttributedString(string: "\n" + subtitle, attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: enabled ? NSColor.secondaryLabelColor : .disabledControlTextColor,
            ]))
        }
        titleLabel.maximumNumberOfLines = 2
        titleLabel.attributedStringValue = text
        frame.size = NSSize(width: max(frame.width, ceil(text.size().width) + 60),
                            height: subtitle == nil ? 28 : 44)
        updateAppearance()
    }

    func addProjectAction(target: AnyObject, action: Selector, index: Int) {
        let button = NSButton(title: "", target: target, action: action)
        button.identifier = NSUserInterfaceItemIdentifier("project-selection-button")
        button.tag = index
        button.frame = bounds
        button.autoresizingMask = [.width, .height]
        button.isBordered = false
        button.isTransparent = true
        button.setAccessibilityLabel(titleLabel.stringValue)
        addSubview(button)
    }

    private func updateAppearance() {
        let primaryColor: NSColor = isMenuHighlighted
            ? .selectedMenuItemTextColor
            : (selectionEnabled ? .labelColor : .disabledControlTextColor)
        let secondaryColor: NSColor = isMenuHighlighted
            ? .selectedMenuItemTextColor
            : (selectionEnabled ? .secondaryLabelColor : .disabledControlTextColor)
        titleLabel.textColor = primaryColor
        detailLabel.textColor = secondaryColor
        checkmark.contentTintColor = selectionEnabled && isSelected && !isMenuHighlighted
            ? .systemBlue : primaryColor
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
    private let schemeResolver: XcodeSchemeResolver
    private let appSettings: AppSettings
    private let onEditProjects: (() -> Void)?
    private let onCatalogChange: (() -> Void)?
    private let confirmMacroAcceptance: () -> Bool
    private let cacheDirectory: URL
    private let makeLauncher: (XcodeProjectLaunchPlan) -> any ProjectLaunching
    private let presentLaunchFailures: ([LaunchFailure]) -> Void
    private let appVersion: String?
    private let openExternalURL: (URL) -> Void
    private let terminateApplication: @MainActor () -> Void
    private let openDestinationSubmenu: (NSMenuItem) -> Void
    private let workingCopyResolver: any GitWorkingCopyResolving
    private let worktreesDirectory: URL
    private let openProjectInXcode: @MainActor (URL) async throws -> Void
    private let presentWorkingCopyError: (String) -> Void
    private var workingCopyStates: [URL: GitRepositoryState] = [:]
    private var workingCopyErrors: [URL: String] = [:]
    private var discoveredWorkingCopies = Set<URL>()
    private var refreshingWorkingCopies = Set<URL>()
    private var workingCopyRefreshIDs: [URL: UUID] = [:]
    private var unvalidatedWorkingCopies = Set<URL>()
    private var isSelectingWorkingCopy = false
    private var isPreparingAutomaticAction = false
    private var trackedSubmenus = Set<ObjectIdentifier>()
    private weak var openMenuButton: NSButton?
    private weak var destinationMenuParent: NSMenuItem?
    private var deferredMenuRefresh = false
    private var refreshingProjectURLs = Set<URL>()
    private var destinationRefreshErrors: [URL: Set<String>] = [:]
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
                        isRefreshing: refreshingProjectURLs.contains(project.activeContainerURL),
                        isSelectedForPlay: configuration.scheme
                            == project.selectedLaunchConfigurationScheme
                    )
                )
            }
        }
        if let projectURL = projectCatalog?.selectedProject?.activeContainerURL {
            let message: String?
            if let failedSchemes = destinationRefreshErrors[projectURL], !failedSchemes.isEmpty {
                message = "Could not refresh \(failedSchemes.sorted().joined(separator: ", ")). Reopen menu to retry."
            } else {
                message = nil
            }
            if let message {
                let item = NSMenuItem(title: message, action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
        }
        addWorkingCopyItems(to: menu)
        menu.addItem(makeCurrentBranchItem())
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
                let row = MenuDetailItemView(title: project.name, detail: "",
                    selection: item.state == .on, showsChevron: false)
                row.addProjectAction(target: self, action: #selector(selectProjectButton(_:)), index: index)
                item.view = row
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
        menu.addItem(makeToggleItem(
            title: "Automatically Select Latest Branch",
            isOn: appSettings.automaticallySelectLatestBranch,
            action: #selector(setAutomaticBranchSelection(_:)),
            help: "Use the branch with the most recent activity. Turn off to choose a branch manually."
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

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === contextMenu else {
            trackedSubmenus.insert(ObjectIdentifier(menu))
            return
        }
        Task { [weak self] in
            await self?.refreshWorkingCopies()
            await self?.refreshDestinations()
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        trackedSubmenus.remove(ObjectIdentifier(menu))
        if menu === contextMenu {
            trackedSubmenus.removeAll()
        }
        if let parent = destinationMenuParent,
           menu === parent.submenu || menu === parent.menu {
            parent.submenu = nil
            destinationMenuParent = nil
        }
        if deferredMenuRefresh && destinationMenuParent == nil && trackedSubmenus.isEmpty {
            deferredMenuRefresh = false
            rebuildContextMenu()
        }
    }

    func refreshDestinations() async {
        guard let project = projectCatalog?.selectedProject,
              !project.enabledConfigurations.isEmpty,
              refreshingProjectURLs.insert(project.activeContainerURL).inserted else {
            return
        }
        destinationRefreshErrors[project.activeContainerURL] = nil
        rebuildContextMenu()
        refreshConfiguration()
        defer {
            refreshingProjectURLs.remove(project.activeContainerURL)
            unvalidatedWorkingCopies.remove(project.activeContainerURL)
            rebuildContextMenu()
            refreshConfiguration()
        }
        let resolver = schemeResolver
        for configuration in project.enabledConfigurations {
            do {
                let destinations = try await Task.detached(priority: .userInitiated) {
                    try resolver.destinations(
                        for: project.activeContainerURL, kind: project.kind, scheme: configuration.scheme
                    )
                }.value
                guard let index = projectCatalog?.projects.firstIndex(where: {
                    $0.url == project.url && $0.activeContainerURL == project.activeContainerURL
                }),
                      projectCatalog?.projects[index].enabledConfigurations.contains(where: {
                          $0.scheme == configuration.scheme
                      }) == true else {
                    continue
                }
                projectCatalog?.updateDestinations(destinations, scheme: configuration.scheme, forProjectAt: index)
                onCatalogChange?()
            } catch {
                destinationRefreshErrors[project.activeContainerURL, default: []].insert(configuration.scheme)
            }
        }
    }

    private func rebuildContextMenu() {
        // Replacing the row while its submenu is tracking would dismiss the picker.
        guard destinationMenuParent == nil && trackedSubmenus.isEmpty else {
            deferredMenuRefresh = true
            refreshVisibleBranchSelection()
            return
        }
        let menu = contextMenu
        let replacement = makeContextMenu()
        menu.removeAllItems()
        for item in replacement.items {
            replacement.removeItem(item)
            menu.addItem(item)
        }
    }

    private var destinationsAreReady: Bool {
        guard let project = projectCatalog?.selectedProject else { return false }
        let selectionFailed = project.selectedLaunchConfiguration.map {
            destinationRefreshErrors[project.activeContainerURL]?.contains($0.scheme) == true
        } ?? false
        return !refreshingProjectURLs.contains(project.activeContainerURL)
            && !unvalidatedWorkingCopies.contains(project.activeContainerURL) && !selectionFailed
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
        isRefreshing: Bool,
        isSelectedForPlay: Bool
    ) -> NSMenuItem {
        let destinationTitle: String
        if isRefreshing {
            destinationTitle = "Refreshing…"
        } else if let destination = configuration.selectedDestination {
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
            selection: isSelectedForPlay,
            showsChevron: false,
            trailingAccessoryWidth: 78
        )
        row.addConfigurationActions(
            target: self,
            selection: [
                "projectPath": projectURL.path,
                "scheme": scheme,
            ],
            destinationMenu: destinationMenu,
            selectSchemeAction: #selector(selectLaunchConfiguration(_:)),
            showDestinationMenuAction: #selector(showButtonSubmenu(_:))
        )
        return row
    }

    private func makePlayItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Run Project", action: #selector(playFromMenu), keyEquivalent: "")
        item.target = self
        let row = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 54))
        row.autoresizingMask = [.width]
        let playButton = NSButton(title: "Run", target: self, action: #selector(playFromMenu))
        playButton.cell = MenuRunButtonCell(textCell: "Run")
        playButton.target = self
        playButton.action = #selector(playFromMenu)
        playButton.identifier = NSUserInterfaceItemIdentifier("run-project-button")
        playButton.bezelStyle = .rounded
        playButton.controlSize = .large
        playButton.font = .systemFont(ofSize: 16, weight: .medium)
        playButton.bezelColor = .systemBlue
        if #available(macOS 26.0, *) {
            playButton.tintProminence = .primary
        }
        playButton.image = menuBarImage(description: "XPlay")
        playButton.imagePosition = .imageLeading
        playButton.setContentHuggingPriority(.defaultLow, for: .horizontal)
        playButton.translatesAutoresizingMaskIntoConstraints = false

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

        let openButton = NSButton(title: "Open", target: self, action: #selector(openFromMenu))
        openButton.identifier = NSUserInterfaceItemIdentifier("open-project-button")
        openButton.bezelStyle = .rounded
        openButton.controlSize = .large
        openButton.font = .systemFont(ofSize: 16, weight: .medium)
        openButton.toolTip = "Open the selected working copy in Xcode"
        openButton.translatesAutoresizingMaskIntoConstraints = false

        let stopButton = CompactStopButton(
            title: "",
            target: self,
            action: #selector(stopFromMenu)
        )
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
        stopButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        stopButton.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(playButton)
        row.addSubview(openButton)
        row.addSubview(stopButton)
        NSLayoutConstraint.activate([
            playButton.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 12),
            playButton.trailingAnchor.constraint(equalTo: openButton.leadingAnchor, constant: -8),
            playButton.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            playButton.heightAnchor.constraint(equalToConstant: 38),
            openButton.trailingAnchor.constraint(equalTo: stopButton.leadingAnchor, constant: -8),
            openButton.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            openButton.widthAnchor.constraint(equalTo: playButton.widthAnchor),
            openButton.heightAnchor.constraint(equalToConstant: 38),
            stopButton.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -12),
            stopButton.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            stopButton.widthAnchor.constraint(equalToConstant: 44),
            stopButton.heightAnchor.constraint(equalToConstant: 38),
            spinner.trailingAnchor.constraint(equalTo: playButton.trailingAnchor, constant: -14),
            spinner.centerYAnchor.constraint(equalTo: playButton.centerYAnchor),
            spinner.widthAnchor.constraint(equalToConstant: 14),
            spinner.heightAnchor.constraint(equalToConstant: 14),
        ])
        item.view = row
        playMenuItem = item
        playMenuButton = playButton
        openMenuButton = openButton
        playMenuSpinner = spinner
        stopMenuButton = stopButton
        updateLaunchButtons()
        return item
    }

    private func updateLaunchButtons() {
        let canStart = !isRunning && canUseSelectedWorkingCopy && destinationsAreReady && projectCatalog?.selectedProject?
            .selectedLaunchConfiguration?.isSelectedDestinationAvailable == true
        let canStop = isRunning && activeLauncher != nil
        let canOpen = projectCatalog?.selectedProject != nil && canUseSelectedWorkingCopy
        playMenuItem?.isEnabled = canStart || canStop || canOpen
        playMenuButton?.isEnabled = canStart
        openMenuButton?.isEnabled = canOpen
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
        item.setAccessibilityLabel("Quit, Command Q")
        let row = MenuDetailItemView(title: "Quit", detail: "⌘Q", showsChevron: false)
        let button = NSButton(title: "", target: self, action: #selector(quitApplication))
        button.identifier = NSUserInterfaceItemIdentifier("quit-button")
        button.isBordered = false
        button.isTransparent = true
        button.setAccessibilityLabel("Quit")
        button.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            button.topAnchor.constraint(equalTo: row.topAnchor),
            button.bottomAnchor.constraint(equalTo: row.bottomAnchor),
        ])
        item.view = row
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
        let row = MenuDetailItemView(
            title: title,
            detail: detail,
            chevronIdentifier: "navigation-chevron"
        )
        let linkButton = ExternalLinkButton(
            title: "",
            target: self,
            action: #selector(openExternalLink(_:))
        )
        linkButton.identifier = NSUserInterfaceItemIdentifier("external-link-button")
        linkButton.externalURL = url
        linkButton.isBordered = false
        linkButton.isTransparent = true
        linkButton.focusRingType = .none
        linkButton.toolTip = toolTip
        linkButton.setAccessibilityLabel(
            detail.isEmpty ? title : "\(title), \(detail)"
        )
        linkButton.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(linkButton)
        NSLayoutConstraint.activate([
            linkButton.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            linkButton.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            linkButton.topAnchor.constraint(equalTo: row.topAnchor),
            linkButton.bottomAnchor.constraint(equalTo: row.bottomAnchor),
        ])
        item.view = row
        item.setAccessibilityLabel(
            detail.isEmpty ? title : "\(title), \(detail)"
        )
        return item
    }

    private func makeSectionHeaderItem(
        title: String, showsEditButton: Bool = false, overflowMenu: NSMenu? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = overflowMenu != nil || (showsEditButton && onEditProjects != nil)

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

        if let overflowMenu {
            let moreButton = NSButton(title: "Show More…", target: self, action: #selector(showButtonSubmenu(_:)))
            moreButton.identifier = NSUserInterfaceItemIdentifier("show-more-branches")
            moreButton.menu = overflowMenu
            moreButton.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            moreButton.isBordered = false
            moreButton.translatesAutoresizingMaskIntoConstraints = false
            headerView.addSubview(moreButton)
            NSLayoutConstraint.activate([
                moreButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -8),
                moreButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
                titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: moreButton.leadingAnchor, constant: -8),
            ])
        } else if showsEditButton {
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
        makeToggleItem(title: "Accept Macros", isOn: appSettings.acceptsMacros,
                       action: #selector(setMacroAcceptance(_:)), help: Self.macroWarningText)
    }

    private func makeToggleItem(title: String, isOn: Bool, action: Selector, help: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = true

        let rowView = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 32))
        rowView.autoresizingMask = [.width]

        let label = NSTextField(labelWithString: title)
        label.font = .menuFont(ofSize: NSFont.systemFontSize)
        label.translatesAutoresizingMaskIntoConstraints = false

        let toggle = MenuTintedSwitch(title: title)
        toggle.controlSize = .small
        toggle.state = isOn ? .on : .off
        toggle.target = self
        toggle.action = action
        toggle.toolTip = help
        toggle.setAccessibilityLabel(title)
        toggle.translatesAutoresizingMaskIntoConstraints = false

        rowView.frame.size.width = max(260, ceil(label.intrinsicContentSize.width
            + toggle.intrinsicContentSize.width + 36))
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
        schemeResolver: XcodeSchemeResolver = XcodeSchemeResolver(),
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
        terminateApplication: @escaping @MainActor () -> Void = { NSApp.terminate(nil) },
        openDestinationSubmenu: @escaping (NSMenuItem) -> Void = { item in
            item.accessibilityPerformPress()
        },
        workingCopyResolver: any GitWorkingCopyResolving = GitWorkingCopyResolver(),
        worktreesDirectory: URL = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appendingPathComponent("XPlay/Worktrees", isDirectory: true),
        openProjectInXcode: @escaping @MainActor (URL) async throws -> Void = { url in
            guard let xcode = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.dt.Xcode") else {
                throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "Xcode is not installed."])
            }
            _ = try await NSWorkspace.shared.open(
                [url], withApplicationAt: xcode, configuration: NSWorkspace.OpenConfiguration()
            )
        },
        presentWorkingCopyError: @escaping (String) -> Void = { message in
            let alert = NSAlert()
            alert.messageText = "Could not use this working copy"
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    ) {
        self.projectCatalog = projectCatalog
        self.schemeResolver = schemeResolver
        self.appSettings = appSettings ?? AppSettings()
        self.onEditProjects = onEditProjects
        self.onCatalogChange = onCatalogChange
        self.confirmMacroAcceptance = confirmMacroAcceptance ?? Self.presentMacroWarning
        self.cacheDirectory = cacheDirectory
        self.makeLauncher = makeLauncher
        self.presentLaunchFailures = presentLaunchFailures ?? Self.presentDefaultLaunchFailures
        self.appVersion = appVersion
        self.openExternalURL = openExternalURL
        self.terminateApplication = terminateApplication
        self.openDestinationSubmenu = openDestinationSubmenu
        self.workingCopyResolver = workingCopyResolver
        self.worktreesDirectory = worktreesDirectory
        self.openProjectInXcode = openProjectInXcode
        self.presentWorkingCopyError = presentWorkingCopyError
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

    private func startProject(refreshLatestBranch: Bool = true) {
        if refreshLatestBranch && appSettings.automaticallySelectLatestBranch {
            Task { [weak self] in
                guard let self, await self.prepareAutomaticAction() else { return }
                self.startProject(refreshLatestBranch: false)
            }
            return
        }
        guard
            !isRunning,
            canUseSelectedWorkingCopy,
            destinationsAreReady,
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
    private func openExternalLink(_ sender: Any) {
        let url = (sender as? ExternalLinkButton)?.externalURL
            ?? (sender as? NSMenuItem)?.representedObject as? URL
        guard let url else { return }
        contextMenu.cancelTracking()
        openExternalURL(url)
    }

    @objc
    private func quitApplication() {
        contextMenu.cancelTracking()
        terminateApplication()
    }

    @objc
    private func editProjects() {
        contextMenu.cancelTracking()
        onEditProjects?()
    }

    @objc
    private func selectProject(_ item: NSMenuItem) {
        selectProject(at: item.tag)
    }

    @objc private func selectProjectButton(_ button: NSButton) {
        contextMenu.cancelTracking()
        selectProject(at: button.tag)
    }

    private func selectProject(at index: Int) {
        projectCatalog?.selectProject(at: index)
        onCatalogChange?()
        contextMenu = makeContextMenu()
        refreshConfiguration()
        Task { [weak self] in
            await self?.refreshWorkingCopies()
            await self?.refreshDestinations()
        }
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
    private func showButtonSubmenu(_ button: NSButton) {
        guard let menu = button.menu, let item = button.enclosingMenuItem else { return }
        destinationMenuParent?.submenu = nil
        destinationMenuParent = item
        menu.delegate = self
        item.submenu = menu
        // Attach only while the accessory menu is open, so the row keeps its
        // independent buttons instead of becoming a full-row submenu trigger.
        openDestinationSubmenu(item)
    }

    private func finishCatalogSelection() {
        onCatalogChange?()
        contextMenu = makeContextMenu()
        refreshConfiguration()
    }

    @objc
    private func setMacroAcceptance(_ toggle: MenuTintedSwitch) {
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
        let canStart = canUseSelectedWorkingCopy && destinationsAreReady && configuration?.isSelectedDestinationAvailable == true
        let description: String
        if let plan = activeLaunchPlan {
            description = "Building and launching \(plan.scheme)…"
        } else if let url = project?.url, refreshingProjectURLs.contains(url) {
            description = "Refreshing destinations…"
        } else if let url = project?.url, let configuration,
                  destinationRefreshErrors[url]?.contains(configuration.scheme) == true {
            description = "Could not refresh destinations. Reopen menu to retry."
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
        button.toolTip = activeLaunchPlan == nil ? "XPlay" : description
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

private extension StatusBarController {
    func currentWorkingCopy(for project: SavedProject) -> GitWorkingCopy? {
        workingCopyStates[project.url]?.workingCopies.first {
            $0.containerURL?.resolvingSymlinksInPath().standardizedFileURL
                == project.activeContainerURL.resolvingSymlinksInPath().standardizedFileURL
        }
    }

    var canUseSelectedWorkingCopy: Bool {
        guard !isSelectingWorkingCopy, !isPreparingAutomaticAction,
              let project = projectCatalog?.selectedProject else { return false }
        if appSettings.automaticallySelectLatestBranch && workingCopyErrors[project.url] != nil { return false }
        guard project.selectedWorkingCopyURL != nil else { return true }
        return workingCopyErrors[project.url] == nil && currentWorkingCopy(for: project) != nil
            && FileManager.default.fileExists(atPath: project.activeContainerURL.path)
    }

    func addWorkingCopyItems(to menu: NSMenu) {
        guard let project = projectCatalog?.selectedProject else { return }
        if let error = workingCopyErrors[project.url] {
            let item = NSMenuItem(title: "Could not read branches. Reopen menu to retry.",
                                  action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.toolTip = error
            menu.addItem(item)
        }
        guard let state = workingCopyStates[project.url] else {
            if !discoveredWorkingCopies.contains(project.url) {
                let item = NSMenuItem(title: "Loading branches…", action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
            return
        }
        var overflowMenu: NSMenu?
        if state.workingCopies.count > 3 {
            let submenu = NSMenu(title: "Branches")
            submenu.autoenablesItems = false
            submenu.delegate = self
            for copy in state.workingCopies.dropFirst(3) {
                submenu.addItem(makeWorkingCopyItem(copy, project: project))
            }
            overflowMenu = submenu
        }
        menu.addItem(makeSectionHeaderItem(title: "Recent Branches", overflowMenu: overflowMenu))
        for copy in state.workingCopies.prefix(3) {
            menu.addItem(makeWorkingCopyItem(copy, project: project))
        }
    }

    func makeWorkingCopyItem(_ copy: GitWorkingCopy, project: SavedProject) -> NSMenuItem {
        let item = NSMenuItem(title: copy.displayName, action: #selector(selectWorkingCopyFromMenu(_:)), keyEquivalent: "")
        item.subtitle = copy.isMainWorktree ? nil : (copy.rootURL == nil ? "New Worktree" : "Worktree")
        item.identifier = NSUserInterfaceItemIdentifier("working-copy")
        item.representedObject = copy.id
        item.target = self
        let row = MenuDetailItemView(title: copy.displayName, detail: "",
            selection: false, showsChevron: false)
        let button = BranchSelectionButton(copy: copy, target: self, action: #selector(selectWorkingCopyButton(_:)))
        row.addSubview(button)
        item.view = row
        item.state = currentWorkingCopy(for: project)?.id == copy.id ? .on : .off
        item.isEnabled = !isSelectingWorkingCopy && !isRunning && !appSettings.automaticallySelectLatestBranch
            && (copy.rootURL == nil || copy.containerURL != nil)
        item.toolTip = workingCopyToolTip(copy)
        button.update(copy: copy, subtitle: item.subtitle,
            selected: item.state == .on, enabled: item.isEnabled)
        row.frame.size = button.frame.size
        button.frame = row.bounds
        button.toolTip = item.toolTip
        return item
    }

    func workingCopyToolTip(_ copy: GitWorkingCopy) -> String {
        let date = DateFormatter.localizedString(from: copy.lastActivity, dateStyle: .medium, timeStyle: .short)
        return [copy.displayName, copy.rootURL?.path ?? "Create a separate worktree when selected",
                copy.isDirty ? "Modified" : nil, "Last activity: \(date)"]
            .compactMap { $0 }.joined(separator: "\n")
    }

    func refreshVisibleBranchSelection() {
        guard let project = projectCatalog?.selectedProject else { return }
        let copies = workingCopyStates[project.url]?.workingCopies ?? []
        var visited = Set<ObjectIdentifier>()
        func refresh(_ menu: NSMenu) {
            guard visited.insert(ObjectIdentifier(menu)).inserted else { return }
            for item in menu.items {
                if let button = item.view?.subviews.compactMap({ $0 as? BranchSelectionButton }).first {
                    // Preparing a new worktree changes its identity from branch to path.
                    let copy = copies.first { $0.id == button.copy.id }
                        ?? copies.first { button.copy.rootURL == nil && $0.branchName == button.copy.branchName }
                        ?? button.copy
                    item.representedObject = copy.id
                    item.subtitle = copy.isMainWorktree ? nil : (copy.rootURL == nil ? "New Worktree" : "Worktree")
                    item.state = currentWorkingCopy(for: project)?.id == copy.id ? .on : .off
                    item.isEnabled = !isSelectingWorkingCopy && !isRunning && !appSettings.automaticallySelectLatestBranch
                        && (copy.rootURL == nil || copy.containerURL != nil)
                    button.update(copy: copy, subtitle: item.subtitle, selected: item.state == .on, enabled: item.isEnabled)
                    item.toolTip = workingCopyToolTip(copy)
                    button.toolTip = item.toolTip
                }
                if let submenu = item.submenu { refresh(submenu) }
                for button in item.view?.subviews.compactMap({ $0 as? NSButton }) ?? [] {
                    if let submenu = button.menu { refresh(submenu) }
                }
            }
        }
        refresh(contextMenu)
        if let header = contextMenu.items.first(where: { $0.identifier?.rawValue == "current-branch" }) {
            let replacement = makeCurrentBranchItem()
            header.title = replacement.title
            header.toolTip = replacement.toolTip
            header.view?.subviews.compactMap { $0 as? NSTextField }.first?.stringValue = replacement.title
        }
    }

    func makeCurrentBranchItem() -> NSMenuItem {
        let title: String
        if isSelectingWorkingCopy {
            title = "Preparing working copy…"
        } else if let project = projectCatalog?.selectedProject {
            if workingCopyErrors[project.url] != nil {
                title = "Branch unavailable"
            } else if let copy = currentWorkingCopy(for: project) {
                title = "Branch: \(copy.displayName)"
            } else if project.selectedWorkingCopyURL != nil {
                title = "Working copy unavailable"
            } else if !discoveredWorkingCopies.contains(project.url) {
                title = "Branch: Loading…"
            } else {
                title = "Local project · No Git repository"
            }
        } else {
            title = "Branch: —"
        }
        let item = makeSectionHeaderItem(title: title)
        item.identifier = NSUserInterfaceItemIdentifier("current-branch")
        item.toolTip = projectCatalog?.selectedProject?.activeContainerURL.path
        return item
    }

    @objc func setAutomaticBranchSelection(_ toggle: MenuTintedSwitch) {
        appSettings.setAutomaticallySelectLatestBranch(toggle.state == .on)
        rebuildContextMenu()
        refreshConfiguration()
        if appSettings.automaticallySelectLatestBranch {
            Task { [weak self] in await self?.refreshWorkingCopies(force: true) }
        }
    }

    func prepareAutomaticAction() async -> Bool {
        guard !isPreparingAutomaticAction, !isSelectingWorkingCopy,
              let project = projectCatalog?.selectedProject else { return false }
        isPreparingAutomaticAction = true
        refreshConfiguration()
        defer {
            isPreparingAutomaticAction = false
            refreshConfiguration()
        }
        await refreshWorkingCopies(force: true)
        await refreshDestinations()
        return projectCatalog?.selectedProject?.url == project.url && workingCopyErrors[project.url] == nil
    }

    @objc func selectWorkingCopyFromMenu(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String else { return }
        Task { [weak self] in await self?.selectWorkingCopy(id: id) }
    }

    @objc func selectWorkingCopyButton(_ button: BranchSelectionButton) {
        Task { [weak self] in await self?.selectWorkingCopy(id: button.copy.id) }
    }

    @objc func openFromMenu() {
        contextMenu.cancelTracking()
        Task { [weak self] in await self?.openSelectedProject() }
    }
}

extension StatusBarController {
    func refreshWorkingCopies(force: Bool = false, selectLatest: Bool = true) async {
        guard let project = projectCatalog?.selectedProject else { return }
        guard force || !refreshingWorkingCopies.contains(project.url) else { return }
        let requestID = UUID()
        workingCopyRefreshIDs[project.url] = requestID
        refreshingWorkingCopies.insert(project.url)
        let resolver = workingCopyResolver
        defer {
            if workingCopyRefreshIDs[project.url] == requestID {
                refreshingWorkingCopies.remove(project.url)
                rebuildContextMenu()
                refreshConfiguration()
            }
        }
        do {
            let state = try await Task.detached(priority: .userInitiated) {
                try resolver.discover(containerURL: project.url)
            }.value
            guard workingCopyRefreshIDs[project.url] == requestID else { return }
            workingCopyStates[project.url] = state
            workingCopyErrors[project.url] = nil
            discoveredWorkingCopies.insert(project.url)
            if selectLatest, appSettings.automaticallySelectLatestBranch, !isRunning,
               projectCatalog?.selectedProject?.url == project.url,
               let latest = state?.workingCopies.first(where: { $0.rootURL == nil || $0.containerURL != nil }),
               let selected = projectCatalog?.selectedProject,
               currentWorkingCopy(for: selected)?.id != latest.id {
                await selectWorkingCopy(id: latest.id, automatic: true)
            }
        } catch {
            guard workingCopyRefreshIDs[project.url] == requestID else { return }
            workingCopyErrors[project.url] = error.localizedDescription
            discoveredWorkingCopies.insert(project.url)
        }
    }

    func selectWorkingCopy(id: String, automatic: Bool = false) async {
        guard !isSelectingWorkingCopy, !isRunning,
              let project = projectCatalog?.selectedProject,
              let copy = workingCopyStates[project.url]?.workingCopies.first(where: { $0.id == id }) else { return }
        isSelectingWorkingCopy = true
        rebuildContextMenu()
        refreshConfiguration()
        let resolver = workingCopyResolver
        let directory = worktreesDirectory
        do {
            let container = try await Task.detached(priority: .userInitiated) {
                try resolver.prepare(copy, for: project.url, worktreesDirectory: directory)
            }.value
            guard (!automatic || appSettings.automaticallySelectLatestBranch),
                  projectCatalog?.selectedProject?.url == project.url,
                  let index = projectCatalog?.projects.firstIndex(where: { $0.url == project.url }) else {
                isSelectingWorkingCopy = false
                rebuildContextMenu()
                refreshConfiguration()
                return
            }
            let isOriginal = container.resolvingSymlinksInPath().standardizedFileURL
                == project.url.resolvingSymlinksInPath().standardizedFileURL
            projectCatalog?.selectWorkingCopy(containerURL: isOriginal ? nil : container, forProjectAt: index)
            if let selected = projectCatalog?.selectedProject {
                unvalidatedWorkingCopies.insert(selected.activeContainerURL)
            }
            onCatalogChange?()
            isSelectingWorkingCopy = false
            await refreshWorkingCopies(force: true, selectLatest: false)
            await refreshDestinations()
        } catch {
            isSelectingWorkingCopy = false
            if automatic { workingCopyErrors[project.url] = error.localizedDescription }
            rebuildContextMenu()
            refreshConfiguration()
            presentWorkingCopyError(error.localizedDescription)
        }
    }

    func openSelectedProject() async {
        if appSettings.automaticallySelectLatestBranch && !isRunning {
            guard await prepareAutomaticAction() else { return }
        }
        guard canUseSelectedWorkingCopy, let project = projectCatalog?.selectedProject else { return }
        do {
            try await openProjectInXcode(project.activeContainerURL)
        } catch {
            presentWorkingCopyError(error.localizedDescription)
        }
    }
}
