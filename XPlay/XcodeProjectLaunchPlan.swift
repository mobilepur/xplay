import Foundation

struct XcodeProjectLaunchPlan: Equatable {
    let containerURL: URL
    let containerKind: XcodeContainerKind
    let scheme: String
    let destination: XcodeDestination
    let derivedDataURL: URL
    let logURL: URL
    let productName: String
    var acceptsMacros = false

    var buildArguments: [String] {
        var arguments = [
            containerKind.xcodebuildArgument, containerURL.path,
            "-scheme", scheme,
            "-configuration", "Debug",
            "-destination", destination.buildSpecifier,
            "-derivedDataPath", derivedDataURL.path,
            "build",
        ]
        if acceptsMacros {
            arguments.insert("-skipMacroValidation", at: 0)
        }
        return arguments
    }

    var buildSettingsArguments: [String] {
        var arguments = buildArguments
        arguments.removeLast()
        arguments.append(contentsOf: ["-showBuildSettings", "-json"])
        return arguments
    }

    var builtAppURL: URL {
        let productsDirectory: String
        switch destination.platform {
        case .macOS:
            productsDirectory = "Debug"
        case .iOSSimulator:
            productsDirectory = "Debug-iphonesimulator"
        }
        return derivedDataURL
            .appendingPathComponent("Build/Products/\(productsDirectory)", isDirectory: true)
            .appendingPathComponent("\(productName).app", isDirectory: true)
    }
}

extension XcodeProjectLaunchPlan {
    static func makeAll(
        for project: SavedProject,
        cacheDirectory: URL,
        acceptsMacros: Bool
    ) -> [Self] {
        project.enabledConfigurations.compactMap { configuration in
            guard
                configuration.isSelectedDestinationAvailable,
                let destination = configuration.selectedDestination
            else {
                return nil
            }
            let filenameScheme = configuration.scheme
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
            return Self(
                containerURL: project.url,
                containerKind: project.kind,
                scheme: configuration.scheme,
                destination: destination,
                derivedDataURL: cacheDirectory
                    .appendingPathComponent("DerivedData", isDirectory: true)
                    .appendingPathComponent(project.name, isDirectory: true)
                    .appendingPathComponent(filenameScheme, isDirectory: true),
                logURL: cacheDirectory
                    .appendingPathComponent("Logs", isDirectory: true)
                    .appendingPathComponent(
                        "\(project.name)-\(filenameScheme)-build.log"
                    ),
                productName: project.name,
                acceptsMacros: acceptsMacros
            )
        }
    }
}
