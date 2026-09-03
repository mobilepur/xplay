import AppKit
import Foundation

final class XcodeProjectLauncher: @unchecked Sendable {
    enum LaunchError: LocalizedError {
        case projectMissing(URL)
        case buildFailed(status: Int32, logURL: URL)
        case productMissing(URL)

        var errorDescription: String? {
            switch self {
            case let .projectMissing(url):
                return "Das Xcode-Projekt wurde nicht gefunden: \(url.path)"
            case let .buildFailed(status, logURL):
                return "Der Build ist mit Status \(status) fehlgeschlagen. Details stehen in \(logURL.path)."
            case let .productMissing(url):
                return "Der Build war erfolgreich, aber \(url.path) wurde nicht gefunden."
            }
        }
    }

    let plan: XcodeProjectLaunchPlan

    var logURL: URL {
        plan.logURL
    }

    init(plan: XcodeProjectLaunchPlan) {
        self.plan = plan
    }

    func launch(completion: @escaping @Sendable (Result<URL, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [plan] in
            do {
                let appURL = try Self.build(plan: plan)

                DispatchQueue.main.async {
                    let configuration = NSWorkspace.OpenConfiguration()
                    configuration.activates = true
                    configuration.createsNewApplicationInstance = false

                    NSWorkspace.shared.openApplication(
                        at: appURL,
                        configuration: configuration
                    ) { _, error in
                        if let error {
                            completion(.failure(error))
                        } else {
                            completion(.success(appURL))
                        }
                    }
                }
            } catch {
                completion(.failure(error))
            }
        }
    }

    private static func build(plan: XcodeProjectLaunchPlan) throws -> URL {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: plan.projectURL.path) else {
            throw LaunchError.projectMissing(plan.projectURL)
        }

        try fileManager.createDirectory(
            at: plan.derivedDataURL,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: plan.logURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        _ = fileManager.createFile(atPath: plan.logURL.path, contents: nil)
        let logHandle = try FileHandle(forWritingTo: plan.logURL)
        defer {
            try? logHandle.close()
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
        process.arguments = plan.buildArguments
        process.currentDirectoryURL = plan.projectURL.deletingLastPathComponent()
        process.standardOutput = logHandle
        process.standardError = logHandle

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw LaunchError.buildFailed(
                status: process.terminationStatus,
                logURL: plan.logURL
            )
        }

        guard fileManager.fileExists(atPath: plan.builtAppURL.path) else {
            throw LaunchError.productMissing(plan.builtAppURL)
        }

        return plan.builtAppURL
    }
}
