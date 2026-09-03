import Foundation

struct SavedProject: Equatable {
    let url: URL

    var name: String {
        url.deletingPathExtension().lastPathComponent
    }
}

@MainActor
final class ProjectCatalog {
    private let defaults: UserDefaults
    private let projectsKey: String
    private let selectedProjectKey: String

    private(set) var projects: [SavedProject]
    private(set) var selectedProject: SavedProject?

    init(defaults: UserDefaults = .standard, storageKey: String = "savedProjects") {
        self.defaults = defaults
        projectsKey = storageKey
        selectedProjectKey = "\(storageKey).selected"

        projects = (defaults.stringArray(forKey: projectsKey) ?? []).map {
            SavedProject(url: URL(fileURLWithPath: $0).standardizedFileURL)
        }

        if
            let selectedPath = defaults.string(forKey: selectedProjectKey),
            let selectedProject = projects.first(where: { $0.url.path == selectedPath })
        {
            self.selectedProject = selectedProject
        } else {
            selectedProject = projects.first
        }
    }

    @discardableResult
    func add(_ url: URL) -> Bool {
        let normalizedURL = url.standardizedFileURL
        guard normalizedURL.pathExtension.lowercased() == "xcodeproj" else {
            return false
        }
        guard !projects.contains(where: { $0.url == normalizedURL }) else {
            return false
        }

        let project = SavedProject(url: normalizedURL)
        projects.append(project)
        selectedProject = project
        persist()
        return true
    }

    func selectProject(at index: Int) {
        guard projects.indices.contains(index) else {
            return
        }

        selectedProject = projects[index]
        persist()
    }

    @discardableResult
    func removeProject(at index: Int) -> Bool {
        guard projects.indices.contains(index) else {
            return false
        }

        let removedProject = projects.remove(at: index)
        if selectedProject == removedProject {
            selectedProject = projects.first
        }
        persist()
        return true
    }

    private func persist() {
        defaults.set(projects.map(\.url.path), forKey: projectsKey)
        defaults.set(selectedProject?.url.path, forKey: selectedProjectKey)
    }
}
