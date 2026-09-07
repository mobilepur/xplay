import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private lazy var projectCatalog = ProjectCatalog()
    private lazy var appSettings = AppSettings()
    private lazy var projectWindowController = ProjectWindowController(
        catalog: projectCatalog,
        onCatalogChange: { [weak self] in
            self?.statusBarController?.projectCatalogDidChange()
        }
    )
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController(
            projectCatalog: projectCatalog,
            appSettings: appSettings,
            onEditProjects: { [weak self] in
                self?.projectWindowController.showProjects()
            },
            onCatalogChange: { [weak self] in
                self?.projectWindowController.refreshFromCatalog()
            }
        )
        Task { [weak self] in
            await self?.statusBarController?.refreshWorkingCopies()
            await self?.statusBarController?.refreshDestinations()
        }
    }
}
