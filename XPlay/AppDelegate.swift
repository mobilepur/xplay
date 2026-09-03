import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private lazy var projectCatalog = ProjectCatalog()
    private lazy var projectWindowController = ProjectWindowController(catalog: projectCatalog)
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController(
            projectCatalog: projectCatalog,
            onEditProjects: { [weak self] in
                self?.projectWindowController.showProjects()
            }
        )
    }
}
