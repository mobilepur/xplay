import AppKit
import Foundation

protocol ProjectLaunching: Sendable {
    var logURL: URL { get }

    func launch(completion: @escaping @Sendable (Result<URL, Error>) -> Void)
}

final class XcodeProjectLauncher: ProjectLaunching, @unchecked Sendable {
    typealias CommandRunner = (
        _ executableURL: URL,
        _ arguments: [String],
        _ currentDirectoryURL: URL?,
        _ outputHandle: FileHandle?
    ) throws -> Int32

    typealias MacApplicationOpener = (
        _ applicationURL: URL,
        _ completion: @escaping @Sendable (Error?) -> Void
    ) -> Void

    typealias BuiltProductResolver = (XcodeProjectLaunchPlan) throws -> URL

    enum LaunchError: LocalizedError {
        case containerMissing(URL)
        case buildFailed(status: Int32, logURL: URL)
        case productMissing(URL)
        case productResolutionFailed(status: Int32, message: String)
        case applicationProductMissing
        case ambiguousApplicationProducts([String])
        case simulatorCommandFailed(command: String, status: Int32, logURL: URL)
        case bundleIdentifierMissing(URL)

        var errorDescription: String? {
            switch self {
            case let .containerMissing(url):
                return "The Xcode container could not be found: \(url.path)"
            case let .buildFailed(status, logURL):
                return "The build failed with status \(status). See \(logURL.path) for details."
            case let .productMissing(url):
                return "The build succeeded, but \(url.path) could not be found."
            case let .productResolutionFailed(status, message):
                return "The built app could not be resolved (xcodebuild status \(status)). \(message)"
            case .applicationProductMissing:
                return "Xcode build settings did not contain an application product."
            case let .ambiguousApplicationProducts(products):
                return "Xcode build settings contained multiple application products: \(products.joined(separator: ", "))."
            case let .simulatorCommandFailed(command, status, logURL):
                return "\(command) failed with status \(status). See \(logURL.path) for details."
            case let .bundleIdentifierMissing(url):
                return "The built app has no bundle identifier: \(url.path)"
            }
        }
    }

    let plan: XcodeProjectLaunchPlan
    private let runCommand: CommandRunner
    private let openMacApplication: MacApplicationOpener
    private let resolveBuiltProduct: BuiltProductResolver

    var logURL: URL {
        plan.logURL
    }

    convenience init(plan: XcodeProjectLaunchPlan) {
        self.init(
            plan: plan,
            runCommand: Self.runProcess,
            openMacApplication: Self.openApplication,
            resolveBuiltProduct: Self.resolveBuiltProduct
        )
    }

    init(
        plan: XcodeProjectLaunchPlan,
        runCommand: @escaping CommandRunner,
        openMacApplication: @escaping MacApplicationOpener,
        resolveBuiltProduct: @escaping BuiltProductResolver = XcodeProjectLauncher.resolveBuiltProduct
    ) {
        self.plan = plan
        self.runCommand = runCommand
        self.openMacApplication = openMacApplication
        self.resolveBuiltProduct = resolveBuiltProduct
    }

    func launch(completion: @escaping @Sendable (Result<URL, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            do {
                let appURL = try build()
                switch plan.destination.platform {
                case .macOS:
                    DispatchQueue.main.async { [openMacApplication] in
                        openMacApplication(appURL) { error in
                            if let error {
                                completion(.failure(error))
                            } else {
                                completion(.success(appURL))
                            }
                        }
                    }
                case .iOSSimulator:
                    try launchOnSimulator(appURL)
                    completion(.success(appURL))
                }
            } catch {
                completion(.failure(error))
            }
        }
    }

    private func build() throws -> URL {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: plan.containerURL.path) else {
            throw LaunchError.containerMissing(plan.containerURL)
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
        defer { try? logHandle.close() }

        let status = try runCommand(
            URL(fileURLWithPath: "/usr/bin/xcodebuild"),
            plan.buildArguments,
            plan.containerURL.deletingLastPathComponent(),
            logHandle
        )
        guard status == 0 else {
            throw LaunchError.buildFailed(status: status, logURL: plan.logURL)
        }
        let resolvedAppURL = try resolveBuiltProduct(plan)
        guard fileManager.fileExists(atPath: resolvedAppURL.path) else {
            throw LaunchError.productMissing(resolvedAppURL)
        }
        return resolvedAppURL
    }

    private func launchOnSimulator(_ appURL: URL) throws {
        let identifier = plan.destination.id
        _ = try runLoggedCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/xcrun"),
            arguments: ["simctl", "boot", identifier],
            allowsFailure: true
        )
        try runLoggedCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/xcrun"),
            arguments: ["simctl", "bootstatus", identifier, "-b"]
        )
        try runLoggedCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/open"),
            arguments: ["-a", "Simulator"]
        )
        try runLoggedCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/xcrun"),
            arguments: ["simctl", "install", identifier, appURL.path]
        )
        guard let bundleIdentifier = bundleIdentifier(for: appURL) else {
            throw LaunchError.bundleIdentifierMissing(appURL)
        }
        try runLoggedCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/xcrun"),
            arguments: ["simctl", "launch", identifier, bundleIdentifier]
        )
    }

    @discardableResult
    private func runLoggedCommand(
        executableURL: URL,
        arguments: [String],
        allowsFailure: Bool = false
    ) throws -> Int32 {
        let logHandle = try FileHandle(forWritingTo: plan.logURL)
        defer { try? logHandle.close() }
        try logHandle.seekToEnd()
        let status = try runCommand(executableURL, arguments, nil, logHandle)
        if status != 0, !allowsFailure {
            throw LaunchError.simulatorCommandFailed(
                command: ([executableURL.lastPathComponent] + arguments).joined(separator: " "),
                status: status,
                logURL: plan.logURL
            )
        }
        return status
    }

    private func bundleIdentifier(for appURL: URL) -> String? {
        let infoURL = appURL.appendingPathComponent("Info.plist")
        guard
            let data = try? Data(contentsOf: infoURL),
            let propertyList = try? PropertyListSerialization.propertyList(
                from: data,
                format: nil
            ) as? [String: Any]
        else {
            return nil
        }
        return propertyList["CFBundleIdentifier"] as? String
    }

    private static func runProcess(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL?,
        outputHandle: FileHandle?
    ) throws -> Int32 {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
        if let outputHandle {
            process.standardOutput = outputHandle
            process.standardError = outputHandle
        }
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private static func resolveBuiltProduct(plan: XcodeProjectLaunchPlan) throws -> URL {
        let result = try XcodeSchemeResolver.runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/xcodebuild"),
            arguments: plan.buildSettingsArguments
        )
        guard result.status == 0 else {
            let message = String(decoding: result.diagnostic, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw LaunchError.productResolutionFailed(status: result.status, message: message)
        }
        return try builtProductURL(
            fromBuildSettings: result.output,
            preferredTargetName: plan.scheme
        )
    }

    static func builtProductURL(
        fromBuildSettings data: Data,
        preferredTargetName: String? = nil
    ) throws -> URL {
        struct TargetSettings: Decodable {
            let target: String?
            let buildSettings: [String: String]
        }

        let targets = try JSONDecoder().decode([TargetSettings].self, from: data)
        let applications = targets.compactMap { target -> (targetName: String?, url: URL)? in
            guard
                let productName = target.buildSettings["FULL_PRODUCT_NAME"],
                (productName as NSString).pathExtension.lowercased() == "app",
                let buildDirectory = target.buildSettings["TARGET_BUILD_DIR"]
            else {
                return nil
            }
            let url = URL(fileURLWithPath: buildDirectory, isDirectory: true)
                .appendingPathComponent(productName, isDirectory: true)
            return (target.buildSettings["TARGET_NAME"] ?? target.target, url)
        }
        if
            let preferredTargetName,
            let application = applications.first(where: {
                $0.targetName == preferredTargetName
            })
        {
            return application.url
        }
        if applications.count == 1, let application = applications.first {
            return application.url
        }
        if applications.count > 1 {
            throw LaunchError.ambiguousApplicationProducts(
                applications.map { $0.url.lastPathComponent }
            )
        }
        throw LaunchError.applicationProductMissing
    }

    private static func openApplication(
        at applicationURL: URL,
        completion: @escaping @Sendable (Error?) -> Void
    ) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        NSWorkspace.shared.openApplication(
            at: applicationURL,
            configuration: configuration
        ) { _, error in
            completion(error)
        }
    }
}
