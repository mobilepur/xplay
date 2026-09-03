import AppKit

@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let progressIndicator: NSProgressIndicator
    private let launcher: XcodeProjectLauncher?

    init(launcher: XcodeProjectLauncher? = nil) {
        self.launcher = launcher
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        progressIndicator = NSProgressIndicator()

        super.init()

        guard let button = statusItem.button else {
            return
        }

        button.image = menuBarImage(named: "play.fill", description: "Projekt starten")
        button.isEnabled = launcher != nil
        button.setAccessibilityLabel(launcher == nil ? "Kein Projekt ausgewählt" : "Projekt starten")
        button.toolTip = launcher == nil ? "Kein Projekt ausgewählt" : "Projekt starten"
        button.target = self
        button.action = #selector(startProject)
        button.sendAction(on: [.leftMouseUp])

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

    @objc
    private func startProject() {
        guard let launcher else {
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

    private func setRunning(_ isRunning: Bool) {
        guard let button = statusItem.button else {
            return
        }

        button.isEnabled = !isRunning && launcher != nil
        button.setAccessibilityLabel(isRunning ? "Projekt wird gestartet" : "Projekt starten")
        button.toolTip = isRunning ? "Projekt wird gebaut und gestartet …" : "Projekt starten"

        if isRunning {
            button.image = nil
            progressIndicator.startAnimation(nil)
        } else {
            progressIndicator.stopAnimation(nil)
            button.image = menuBarImage(named: "play.fill", description: "Projekt starten")
        }
    }

    private func showFailure(_ error: Error, logURL: URL) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Das Projekt konnte nicht gestartet werden"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "Build-Log öffnen")
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
