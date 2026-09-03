import Foundation

struct XcodeProjectLaunchPlan: Equatable {
    let projectURL: URL
    let scheme: String
    let derivedDataURL: URL
    let logURL: URL
    let productName: String

    var buildArguments: [String] {
        [
            "-project", projectURL.path,
            "-scheme", scheme,
            "-configuration", "Debug",
            "-destination", "platform=macOS",
            "-derivedDataPath", derivedDataURL.path,
            "build",
        ]
    }

    var builtAppURL: URL {
        derivedDataURL
            .appendingPathComponent("Build/Products/Debug", isDirectory: true)
            .appendingPathComponent("\(productName).app", isDirectory: true)
    }
}
