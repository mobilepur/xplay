import Foundation

enum XcodeContainerKind: String, Codable, Equatable {
    case project
    case workspace

    var xcodebuildArgument: String {
        switch self {
        case .project:
            return "-project"
        case .workspace:
            return "-workspace"
        }
    }
}

struct XcodeDestination: Codable, Equatable, Hashable {
    enum Platform: String, Codable {
        case macOS
        case iOSSimulator
    }

    let platform: Platform
    let id: String
    let name: String
    let osVersion: String?

    init(platform: Platform, id: String, name: String, osVersion: String? = nil) {
        self.platform = platform
        self.id = id
        self.name = name
        self.osVersion = osVersion
    }

    var displayName: String {
        guard let osVersion else {
            return name
        }
        return "\(name) (\(osVersion))"
    }

    var buildSpecifier: String {
        switch platform {
        case .macOS:
            return "platform=macOS,id=\(id)"
        case .iOSSimulator:
            return "platform=iOS Simulator,id=\(id)"
        }
    }
}

struct LaunchConfiguration: Codable, Equatable {
    let scheme: String
    var isEnabled: Bool
    var availableDestinations: [XcodeDestination]
    var selectedDestinationID: String?
    var unavailableDestination: XcodeDestination?

    init(
        scheme: String,
        isEnabled: Bool = false,
        availableDestinations: [XcodeDestination] = [],
        selectedDestinationID: String? = nil,
        unavailableDestination: XcodeDestination? = nil
    ) {
        self.scheme = scheme
        self.isEnabled = isEnabled
        self.availableDestinations = availableDestinations
        self.selectedDestinationID = selectedDestinationID
        self.unavailableDestination = unavailableDestination
    }

    var selectedDestination: XcodeDestination? {
        guard let selectedDestinationID else {
            return nil
        }
        return availableDestinations.first { $0.id == selectedDestinationID }
            ?? unavailableDestination.flatMap { destination in
                destination.id == selectedDestinationID ? destination : nil
            }
    }

    var isSelectedDestinationAvailable: Bool {
        guard let selectedDestinationID else {
            return false
        }
        return availableDestinations.contains { $0.id == selectedDestinationID }
    }
}

struct SavedProject: Codable, Equatable {
    let url: URL
    let kind: XcodeContainerKind
    var configurations: [LaunchConfiguration]

    init(
        url: URL,
        kind: XcodeContainerKind,
        configurations: [LaunchConfiguration] = []
    ) {
        self.url = url.standardizedFileURL
        self.kind = kind
        self.configurations = configurations
    }

    var name: String {
        url.deletingPathExtension().lastPathComponent
    }

    var schemes: [String] {
        configurations.map(\.scheme)
    }

    var enabledConfigurations: [LaunchConfiguration] {
        configurations.filter(\.isEnabled)
    }
}

@MainActor
final class ProjectCatalog {
    private let defaults: UserDefaults
    private let selectedProjectKey: String
    private let recordsKey: String

    private(set) var projects: [SavedProject]
    private(set) var selectedProject: SavedProject?

    init(defaults: UserDefaults = .standard, storageKey: String = "savedProjects") {
        self.defaults = defaults
        selectedProjectKey = "\(storageKey).selected"
        recordsKey = "\(storageKey).records.v2"

        if
            let data = defaults.data(forKey: recordsKey),
            let decodedProjects = try? JSONDecoder().decode([SavedProject].self, from: data)
        {
            projects = decodedProjects.map {
                SavedProject(
                    url: $0.url,
                    kind: $0.kind,
                    configurations: $0.configurations
                )
            }
        } else {
            projects = Self.migrateLegacyProjects(defaults: defaults, storageKey: storageKey)
        }

        if
            let selectedPath = defaults.string(forKey: selectedProjectKey),
            let selectedProject = projects.first(where: { $0.url.path == selectedPath })
        {
            self.selectedProject = selectedProject
        } else {
            selectedProject = projects.first
        }

        persist()
    }

    @discardableResult
    func add(_ url: URL, schemes: [String] = []) -> Bool {
        let normalizedURL = url.standardizedFileURL
        guard let kind = Self.containerKind(for: normalizedURL) else {
            return false
        }
        guard !projects.contains(where: { $0.url == normalizedURL }) else {
            return false
        }

        let project = SavedProject(
            url: normalizedURL,
            kind: kind,
            configurations: normalizedSchemes(schemes).map { scheme in
                LaunchConfiguration(scheme: scheme)
            }
        )
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

    func updateSchemes(_ schemes: [String], forProjectAt index: Int) {
        guard projects.indices.contains(index) else {
            return
        }

        let existing = Dictionary(
            uniqueKeysWithValues: projects[index].configurations.map { ($0.scheme, $0) }
        )
        projects[index].configurations = normalizedSchemes(schemes).map { scheme in
            existing[scheme] ?? LaunchConfiguration(scheme: scheme)
        }
        finishProjectMutation(at: index)
    }

    func setSchemeEnabled(_ isEnabled: Bool, scheme: String, forProjectAt index: Int) {
        guard
            projects.indices.contains(index),
            let configurationIndex = projects[index].configurations.firstIndex(
                where: { $0.scheme == scheme }
            )
        else {
            return
        }

        projects[index].configurations[configurationIndex].isEnabled = isEnabled
        finishProjectMutation(at: index)
    }

    func updateDestinations(
        _ destinations: [XcodeDestination],
        scheme: String,
        forProjectAt index: Int
    ) {
        guard
            projects.indices.contains(index),
            let configurationIndex = projects[index].configurations.firstIndex(
                where: { $0.scheme == scheme }
            )
        else {
            return
        }

        let previousConfiguration = projects[index].configurations[configurationIndex]
        let previousSelection = previousConfiguration.selectedDestinationID
        let previousDestination = previousConfiguration.selectedDestination
        let selectedDestinationID: String?
        let unavailableDestination: XcodeDestination?
        if let previousSelection, destinations.contains(where: { $0.id == previousSelection }) {
            selectedDestinationID = previousSelection
            unavailableDestination = nil
        } else if let previousSelection {
            selectedDestinationID = previousSelection
            unavailableDestination = previousDestination
        } else if destinations.count == 1 {
            selectedDestinationID = destinations[0].id
            unavailableDestination = nil
        } else {
            selectedDestinationID = nil
            unavailableDestination = nil
        }

        projects[index].configurations[configurationIndex].availableDestinations = destinations
        projects[index].configurations[configurationIndex].selectedDestinationID = selectedDestinationID
        projects[index].configurations[configurationIndex].unavailableDestination = unavailableDestination
        finishProjectMutation(at: index)
    }

    func selectDestination(id: String, scheme: String, forProjectAt index: Int) {
        guard
            projects.indices.contains(index),
            let configurationIndex = projects[index].configurations.firstIndex(
                where: { $0.scheme == scheme }
            ),
            projects[index].configurations[configurationIndex]
                .availableDestinations.contains(where: { $0.id == id })
        else {
            return
        }

        projects[index].configurations[configurationIndex].selectedDestinationID = id
        projects[index].configurations[configurationIndex].unavailableDestination = nil
        finishProjectMutation(at: index)
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

    private func finishProjectMutation(at index: Int) {
        if selectedProject?.url == projects[index].url {
            selectedProject = projects[index]
        }
        persist()
    }

    private func persist() {
        defaults.set(try? JSONEncoder().encode(projects), forKey: recordsKey)
        defaults.set(selectedProject?.url.path, forKey: selectedProjectKey)
    }

    private func normalizedSchemes(_ schemes: [String]) -> [String] {
        Self.normalizedSchemes(schemes)
    }

    private static func normalizedSchemes(_ schemes: [String]) -> [String] {
        schemes.reduce(into: [String]()) { result, scheme in
            if !scheme.isEmpty, !result.contains(scheme) {
                result.append(scheme)
            }
        }
    }

    private static func containerKind(for url: URL) -> XcodeContainerKind? {
        switch url.pathExtension.lowercased() {
        case "xcodeproj":
            return .project
        case "xcworkspace":
            return .workspace
        default:
            return nil
        }
    }

    private static func migrateLegacyProjects(
        defaults: UserDefaults,
        storageKey: String
    ) -> [SavedProject] {
        let schemesKey = "\(storageKey).schemes"
        let selectedSchemesKey = "\(storageKey).selectedSchemes"
        let storedSchemes = defaults.dictionary(forKey: schemesKey) as? [String: [String]] ?? [:]
        let storedSelectedSchemes = defaults.dictionary(forKey: selectedSchemesKey) as? [String: String] ?? [:]

        return (defaults.stringArray(forKey: storageKey) ?? []).compactMap { path in
            let url = URL(fileURLWithPath: path).standardizedFileURL
            guard let kind = containerKind(for: url) else {
                return nil
            }
            let schemes = normalizedSchemes(storedSchemes[url.path] ?? [])
            let selectedScheme = storedSelectedSchemes[url.path].flatMap { selection in
                schemes.contains(selection) ? selection : nil
            } ?? schemes.first
            return SavedProject(
                url: url,
                kind: kind,
                configurations: schemes.map { scheme in
                    LaunchConfiguration(scheme: scheme, isEnabled: scheme == selectedScheme)
                }
            )
        }
    }
}
