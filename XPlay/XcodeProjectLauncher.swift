import AppKit
import Foundation

protocol ProjectLaunching: Sendable {
    var logURL: URL { get }

    func launch(completion: @escaping @Sendable (Result<URL, Error>) -> Void)
    func cancel()
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
    typealias CapturedCommandRunner = (
        _ executableURL: URL,
        _ arguments: [String]
    ) throws -> XcodeSchemeResolver.ProcessResult
    typealias CommandCanceller = () -> Void

    enum LaunchError: LocalizedError {
        case containerMissing(URL)
        case buildFailed(status: Int32, logURL: URL)
        case productMissing(URL)
        case productResolutionFailed(status: Int32, message: String)
        case applicationProductMissing
        case ambiguousApplicationProducts([String])
        case simulatorCommandFailed(command: String, status: Int32, logURL: URL)
        case bundleIdentifierMissing(URL)
        case applicationTerminationFailed(URL)

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
            case let .applicationTerminationFailed(url):
                return "The running app could not be closed: \(url.path). Quit it and try Play again."
            case let .bundleIdentifierMissing(url):
                return "The built app has no bundle identifier: \(url.path)"
            }
        }
    }

    let plan: XcodeProjectLaunchPlan
    private let runCommand: CommandRunner
    private let cancelCommand: CommandCanceller
    private let openMacApplication: MacApplicationOpener
    private let resolveBuiltProduct: BuiltProductResolver
    private let buildCache: BuildCache?
    private let stateLock = NSLock()
    private var isCancelled = false

    var logURL: URL {
        plan.logURL
    }

    convenience init(plan: XcodeProjectLaunchPlan) {
        let commandRunner = CancellableProcessRunner()
        self.init(
            plan: plan,
            runCommand: commandRunner.run,
            runCapturedCommand: commandRunner.capture,
            cancelCommand: commandRunner.cancel,
            openMacApplication: Self.openApplication,
            buildCache: .shared
        )
    }

    init(
        plan: XcodeProjectLaunchPlan,
        runCommand: @escaping CommandRunner,
        runCapturedCommand: @escaping CapturedCommandRunner = { executableURL, arguments in
            try XcodeSchemeResolver.runProcess(
                executableURL: executableURL,
                arguments: arguments
            )
        },
        cancelCommand: @escaping CommandCanceller = {},
        openMacApplication: @escaping MacApplicationOpener,
        resolveBuiltProduct: BuiltProductResolver? = nil,
        buildCache: BuildCache? = nil
    ) {
        self.plan = plan
        self.runCommand = runCommand
        self.cancelCommand = cancelCommand
        self.openMacApplication = openMacApplication
        self.buildCache = buildCache
        self.resolveBuiltProduct = resolveBuiltProduct ?? { plan in
            try Self.resolveBuiltProduct(
                plan: plan,
                runCapturedCommand: runCapturedCommand
            )
        }
    }

    func launch(completion: @escaping @Sendable (Result<URL, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            do {
                try throwIfCancelled()
                let lease = try buildCache?.beginUsing(plan.derivedDataURL)
                performLaunch { result in
                    lease?.finish()
                    completion(result)
                }
            } catch {
                completion(.failure(error))
            }
        }
    }

    private func performLaunch(completion: @escaping @Sendable (Result<URL, Error>) -> Void) {
        do {
            try throwIfCancelled()
            let appURL = try build()
            try throwIfCancelled()
            switch plan.destination.platform {
            case .macOS:
                DispatchQueue.main.async { [self] in
                    restartMacApplication(at: appURL, completion: completion)
                }
            case .iOSSimulator:
                try launchOnSimulator(appURL)
                completion(.success(appURL))
            }
        } catch {
            completion(.failure(error))
        }
    }

    private func restartMacApplication(
        at appURL: URL,
        completion: @escaping @Sendable (Result<URL, Error>) -> Void
    ) {
        let canonicalURL = appURL.resolvingSymlinksInPath().standardizedFileURL
        let runningApplications = NSWorkspace.shared.runningApplications.filter {
            $0.bundleURL?.resolvingSymlinksInPath().standardizedFileURL == canonicalURL
                && !$0.isTerminated
        }
        do {
            for application in runningApplications {
                try throwIfCancelled()
                guard application.terminate() || application.isTerminated else {
                    throw LaunchError.applicationTerminationFailed(appURL)
                }
            }
        } catch {
            completion(.failure(error))
            return
        }
        // A normal quit can be delayed by a save dialog. Never force it or open
        // a second copy while the previous executable is still running.
        openMacApplicationAfterTermination(
            runningApplications,
            appURL: appURL,
            deadline: ProcessInfo.processInfo.systemUptime + 10,
            completion: completion
        )
    }

    private func openMacApplicationAfterTermination(
        _ applications: [NSRunningApplication],
        appURL: URL,
        deadline: TimeInterval,
        completion: @escaping @Sendable (Result<URL, Error>) -> Void
    ) {
        guard !cancellationRequested else {
            completion(.failure(CancellationError()))
            return
        }
        if applications.contains(where: { !$0.isTerminated }) {
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                completion(.failure(LaunchError.applicationTerminationFailed(appURL)))
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [self] in
                openMacApplicationAfterTermination(
                    applications, appURL: appURL, deadline: deadline, completion: completion
                )
            }
            return
        }
        openMacApplication(appURL) { [self] error in
            if let error {
                completion(.failure(error))
            } else if cancellationRequested {
                completion(.failure(CancellationError()))
            } else {
                completion(.success(appURL))
            }
        }
    }

    func cancel() {
        stateLock.withLock {
            isCancelled = true
        }
        cancelCommand()
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
        try throwIfCancelled()
        guard status == 0 else {
            throw LaunchError.buildFailed(status: status, logURL: plan.logURL)
        }
        let resolvedAppURL = try resolveBuiltProduct(plan)
        try throwIfCancelled()
        guard fileManager.fileExists(atPath: resolvedAppURL.path) else {
            throw LaunchError.productMissing(resolvedAppURL)
        }
        return resolvedAppURL
    }

    private func launchOnSimulator(_ appURL: URL) throws {
        try throwIfCancelled()
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
        try throwIfCancelled()
        let logHandle = try FileHandle(forWritingTo: plan.logURL)
        defer { try? logHandle.close() }
        try logHandle.seekToEnd()
        let status = try runCommand(executableURL, arguments, nil, logHandle)
        try throwIfCancelled()
        if status != 0, !allowsFailure {
            throw LaunchError.simulatorCommandFailed(
                command: ([executableURL.lastPathComponent] + arguments).joined(separator: " "),
                status: status,
                logURL: plan.logURL
            )
        }
        return status
    }

    private var cancellationRequested: Bool {
        stateLock.withLock { isCancelled }
    }

    private func throwIfCancelled() throws {
        if cancellationRequested {
            throw CancellationError()
        }
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

    private static func resolveBuiltProduct(
        plan: XcodeProjectLaunchPlan,
        runCapturedCommand: CapturedCommandRunner
    ) throws -> URL {
        let result = try runCapturedCommand(
            URL(fileURLWithPath: "/usr/bin/xcodebuild"),
            plan.buildSettingsArguments
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

    static func openApplication(
        at applicationURL: URL,
        completion: @escaping @Sendable (Error?) -> Void
    ) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(
            at: applicationURL,
            configuration: configuration
        ) { _, error in
            completion(error)
        }
    }
}

private final class CancellableProcessRunner: @unchecked Sendable {
    private final class DataBox: @unchecked Sendable {
        var data = Data()
    }

    private let lock = NSLock()
    private var activeProcess: Process?
    private var isCancelled = false

    func run(
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

        let status = try execute(process)
        try throwIfCancelled()
        return status
    }

    func capture(
        executableURL: URL,
        arguments: [String]
    ) throws -> XcodeSchemeResolver.ProcessResult {
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        let output = DataBox()
        let diagnostic = DataBox()
        let readers = DispatchGroup()

        let status = try execute(process) {
            readers.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                output.data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                readers.leave()
            }
            readers.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                diagnostic.data = errorPipe.fileHandleForReading.readDataToEndOfFile()
                readers.leave()
            }
        }
        readers.wait()
        try throwIfCancelled()
        return XcodeSchemeResolver.ProcessResult(
            status: status,
            output: output.data,
            diagnostic: diagnostic.data
        )
    }

    private func execute(_ process: Process, didStart: () -> Void = {}) throws -> Int32 {
        try lock.withLock {
            guard !isCancelled else {
                throw CancellationError()
            }
            activeProcess = process
        }
        do {
            try process.run()
        } catch {
            clear(process)
            throw error
        }
        didStart()
        if lock.withLock({ isCancelled }), process.isRunning {
            process.interrupt()
        }
        process.waitUntilExit()
        clear(process)
        return process.terminationStatus
    }

    func cancel() {
        let process = lock.withLock { () -> Process? in
            isCancelled = true
            return activeProcess
        }
        if process?.isRunning == true {
            process?.interrupt()
        }
    }

    private func clear(_ process: Process) {
        lock.withLock {
            if activeProcess === process {
                activeProcess = nil
            }
        }
    }

    private func throwIfCancelled() throws {
        if lock.withLock({ isCancelled }) {
            throw CancellationError()
        }
    }
}
