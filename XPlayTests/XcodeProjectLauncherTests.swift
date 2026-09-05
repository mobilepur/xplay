import AppKit
import Foundation
import XCTest
@testable import XPlay

final class XcodeProjectLauncherTests: XCTestCase {
    func testRepeatedMacLaunchRunsRebuiltBinaryAndLeavesOtherCopyRunning() throws {
        let fixture = try MacApplicationFixture()
        defer { fixture.cleanUp() }
        try fixture.build(version: "first")
        let first = try openFixtureApplication(fixture.appURL)
        try waitForMarker(fixture.markerURL, value: "first")

        let otherURL = fixture.directory.appendingPathComponent("Other.app")
        try FileManager.default.copyItem(at: fixture.appURL, to: otherURL)
        let other = try openFixtureApplication(otherURL)
        try fixture.build(version: "second")

        let launcher = XcodeProjectLauncher(
            plan: fixture.plan,
            runCommand: { _, _, _, _ in 0 },
            openMacApplication: XcodeProjectLauncher.openApplication,
            resolveBuiltProduct: { _ in fixture.appURL }
        )
        let finished = expectation(description: "rebuilt app opened")
        let result = LaunchResultBox()
        launcher.launch {
            result.set($0)
            finished.fulfill()
        }
        wait(for: [finished], timeout: 15)

        XCTAssertEqual(try result.value?.get(), fixture.appURL)
        XCTAssertTrue(first.isTerminated, "The old executable must exit before launching its replacement")
        XCTAssertFalse(other.isTerminated, "A different app URL with the same bundle ID must remain running")
        try waitForMarker(fixture.markerURL, value: "second")
    }

    func testMacLaunchReportsRefusedQuitWithoutOpeningAnotherInstance() throws {
        let fixture = try MacApplicationFixture()
        defer { fixture.cleanUp() }
        try fixture.build(version: "first", refusesTermination: true)
        let running = try openFixtureApplication(fixture.appURL)
        try waitForMarker(fixture.markerURL, value: "first")
        let opened = URLBox()
        let launcher = XcodeProjectLauncher(
            plan: fixture.plan,
            runCommand: { _, _, _, _ in 0 },
            openMacApplication: { url, completion in
                opened.set(url)
                completion(nil)
            },
            resolveBuiltProduct: { _ in fixture.appURL }
        )
        let finished = expectation(description: "refused quit reported")
        let result = LaunchResultBox()
        launcher.launch {
            result.set($0)
            finished.fulfill()
        }
        wait(for: [finished], timeout: 15)

        XCTAssertThrowsError(try result.value?.get()) { error in
            guard case XcodeProjectLauncher.LaunchError.applicationTerminationFailed = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertFalse(running.isTerminated)
        XCTAssertNil(opened.value)
    }

    func testCancelWhileMacApplicationIsQuittingDoesNotReopenIt() throws {
        let fixture = try MacApplicationFixture()
        defer { fixture.cleanUp() }
        try fixture.build(version: "first", refusesTermination: true)
        let running = try openFixtureApplication(fixture.appURL)
        try waitForMarker(fixture.markerURL, value: "first")
        let opened = URLBox()
        let launcher = XcodeProjectLauncher(
            plan: fixture.plan,
            runCommand: { _, _, _, _ in 0 },
            openMacApplication: { url, completion in
                opened.set(url)
                completion(nil)
            },
            resolveBuiltProduct: { _ in fixture.appURL }
        )
        let finished = expectation(description: "quit wait cancelled")
        let result = LaunchResultBox()
        launcher.launch {
            result.set($0)
            finished.fulfill()
        }
        try waitForMarker(fixture.quitMarkerURL, value: "requested")
        launcher.cancel()
        wait(for: [finished], timeout: 2)

        XCTAssertThrowsError(try result.value?.get()) { error in
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertFalse(running.isTerminated)
        XCTAssertNil(opened.value)
    }

    private func openFixtureApplication(_ url: URL) throws -> NSRunningApplication {
        let opened = expectation(description: "fixture opened")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.createsNewApplicationInstance = true
        var application: NSRunningApplication?
        var launchError: Error?
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, error in
            application = app
            launchError = error
            opened.fulfill()
        }
        wait(for: [opened], timeout: 10)
        if let launchError { throw launchError }
        return try XCTUnwrap(application)
    }

    private func waitForMarker(_ url: URL, value: String) throws {
        let matchingMarker = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                (try? String(contentsOf: url, encoding: .utf8)) == value
            },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [matchingMarker], timeout: 5), .completed)
    }

    func testCancelInterruptsActiveBuildAndDoesNotOpenApplication() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("XcodeProjectLauncherTests.\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let workspaceURL = temporaryDirectory.appendingPathComponent("Workspace.xcworkspace")
        try FileManager.default.createDirectory(
            at: workspaceURL,
            withIntermediateDirectories: true
        )
        let plan = XcodeProjectLaunchPlan(
            containerURL: workspaceURL,
            containerKind: .workspace,
            scheme: "Desktop",
            destination: XcodeDestination(platform: .macOS, id: "mac", name: "My Mac"),
            derivedDataURL: temporaryDirectory.appendingPathComponent("DerivedData"),
            logURL: temporaryDirectory.appendingPathComponent("Logs/build.log"),
            productName: "Workspace"
        )
        let commandStarted = expectation(description: "build command started")
        let commandCancelled = DispatchSemaphore(value: 0)
        let openedApplication = URLBox()
        let launcher = XcodeProjectLauncher(
            plan: plan,
            runCommand: { _, _, _, _ in
                commandStarted.fulfill()
                commandCancelled.wait()
                return 0
            },
            cancelCommand: {
                commandCancelled.signal()
            },
            openMacApplication: { applicationURL, completion in
                openedApplication.set(applicationURL)
                completion(nil)
            },
            resolveBuiltProduct: { _ in
                XCTFail("A cancelled build must not resolve or open its product")
                return plan.builtAppURL
            }
        )
        let finished = expectation(description: "cancelled launch finished")
        let launchResult = LaunchResultBox()

        launcher.launch { result in
            launchResult.set(result)
            finished.fulfill()
        }
        wait(for: [commandStarted], timeout: 2)
        launcher.cancel()
        wait(for: [finished], timeout: 2)

        XCTAssertThrowsError(try launchResult.value?.get()) { error in
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertNil(openedApplication.value)
    }

    func testCancelInterruptsProductResolutionCommand() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("XcodeProjectLauncherTests.\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let workspaceURL = temporaryDirectory.appendingPathComponent("Workspace.xcworkspace")
        try FileManager.default.createDirectory(
            at: workspaceURL,
            withIntermediateDirectories: true
        )
        let plan = XcodeProjectLaunchPlan(
            containerURL: workspaceURL,
            containerKind: .workspace,
            scheme: "Desktop",
            destination: XcodeDestination(platform: .macOS, id: "mac", name: "My Mac"),
            derivedDataURL: temporaryDirectory.appendingPathComponent("DerivedData"),
            logURL: temporaryDirectory.appendingPathComponent("Logs/build.log"),
            productName: "Workspace"
        )
        let resolutionStarted = expectation(description: "product resolution started")
        let commandCancelled = DispatchSemaphore(value: 0)
        let openedApplication = URLBox()
        let launcher = XcodeProjectLauncher(
            plan: plan,
            runCommand: { _, _, _, _ in 0 },
            runCapturedCommand: { executableURL, arguments in
                XCTAssertEqual(executableURL.path, "/usr/bin/xcodebuild")
                XCTAssertEqual(arguments, plan.buildSettingsArguments)
                resolutionStarted.fulfill()
                commandCancelled.wait()
                throw CancellationError()
            },
            cancelCommand: {
                commandCancelled.signal()
            },
            openMacApplication: { applicationURL, completion in
                openedApplication.set(applicationURL)
                completion(nil)
            }
        )
        let finished = expectation(description: "cancelled resolution finished")
        let launchResult = LaunchResultBox()

        launcher.launch { result in
            launchResult.set(result)
            finished.fulfill()
        }
        wait(for: [resolutionStarted], timeout: 2)
        launcher.cancel()
        wait(for: [finished], timeout: 2)

        XCTAssertThrowsError(try launchResult.value?.get()) { error in
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertNil(openedApplication.value)
    }

    func testMacLaunchUsesResolvedProductWhenAppNameDiffersFromWorkspace() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("XcodeProjectLauncherTests.\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let workspaceURL = temporaryDirectory.appendingPathComponent("Workspace.xcworkspace")
        try FileManager.default.createDirectory(
            at: workspaceURL,
            withIntermediateDirectories: true
        )
        let plan = XcodeProjectLaunchPlan(
            containerURL: workspaceURL,
            containerKind: .workspace,
            scheme: "Desktop",
            destination: XcodeDestination(platform: .macOS, id: "mac", name: "My Mac"),
            derivedDataURL: temporaryDirectory.appendingPathComponent("DerivedData"),
            logURL: temporaryDirectory.appendingPathComponent("Logs/build.log"),
            productName: "Workspace"
        )
        let actualAppURL = plan.builtAppURL.deletingLastPathComponent()
            .appendingPathComponent("ActualDesktopApp.app")
        try FileManager.default.createDirectory(
            at: plan.builtAppURL,
            withIntermediateDirectories: true
        )
        let openedApplication = URLBox()
        let launcher = XcodeProjectLauncher(
            plan: plan,
            runCommand: { _, _, _, _ in
                try FileManager.default.createDirectory(
                    at: actualAppURL,
                    withIntermediateDirectories: true
                )
                return 0
            },
            openMacApplication: { applicationURL, completion in
                openedApplication.set(applicationURL)
                completion(nil)
            },
            resolveBuiltProduct: { receivedPlan in
                XCTAssertEqual(receivedPlan, plan)
                return actualAppURL
            }
        )
        let finished = expectation(description: "macOS app launched")
        let launchResult = LaunchResultBox()

        launcher.launch { result in
            launchResult.set(result)
            finished.fulfill()
        }
        wait(for: [finished], timeout: 2)

        XCTAssertEqual(try launchResult.value?.get(), actualAppURL)
        XCTAssertEqual(openedApplication.value, actualAppURL)
    }

    func testSimulatorBuildBootInstallAndLaunchSequence() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("XcodeProjectLauncherTests.\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let workspaceURL = temporaryDirectory.appendingPathComponent("Example.xcworkspace")
        try FileManager.default.createDirectory(
            at: workspaceURL,
            withIntermediateDirectories: true
        )
        let destination = XcodeDestination(
            platform: .iOSSimulator,
            id: "sim-id",
            name: "iPhone 17 Pro"
        )
        let plan = XcodeProjectLaunchPlan(
            containerURL: workspaceURL,
            containerKind: .workspace,
            scheme: "Example-iOS",
            destination: destination,
            derivedDataURL: temporaryDirectory.appendingPathComponent("DerivedData"),
            logURL: temporaryDirectory.appendingPathComponent("Logs/build.log"),
            productName: "Workspace"
        )
        let actualAppURL = plan.builtAppURL.deletingLastPathComponent()
            .appendingPathComponent("ActualApp.app")
        try FileManager.default.createDirectory(
            at: plan.builtAppURL,
            withIntermediateDirectories: true
        )
        let staleInfo: NSDictionary = ["CFBundleIdentifier": "com.example.stale"]
        XCTAssertTrue(
            staleInfo.write(
                to: plan.builtAppURL.appendingPathComponent("Info.plist"),
                atomically: true
            )
        )
        let commands = CommandBox()
        let launcher = XcodeProjectLauncher(
            plan: plan,
            runCommand: { executableURL, arguments, _, _ in
                commands.append(RecordedCommand(executable: executableURL.path, arguments: arguments))
                if executableURL.path == "/usr/bin/xcodebuild" {
                    try FileManager.default.createDirectory(
                        at: actualAppURL,
                        withIntermediateDirectories: true
                    )
                    let info: NSDictionary = ["CFBundleIdentifier": "com.example.app"]
                    XCTAssertTrue(
                        info.write(
                            to: actualAppURL.appendingPathComponent("Info.plist"),
                            atomically: true
                        )
                    )
                }
                return 0
            },
            openMacApplication: { _, completion in
                completion(nil)
            },
            resolveBuiltProduct: { receivedPlan in
                XCTAssertEqual(receivedPlan, plan)
                return actualAppURL
            }
        )
        let finished = expectation(description: "Simulator app launched")
        let launchResult = LaunchResultBox()

        launcher.launch { result in
            launchResult.set(result)
            finished.fulfill()
        }
        wait(for: [finished], timeout: 2)

        XCTAssertEqual(try launchResult.value?.get(), actualAppURL)
        XCTAssertEqual(
            commands.values,
            [
                RecordedCommand(executable: "/usr/bin/xcodebuild", arguments: plan.buildArguments),
                RecordedCommand(executable: "/usr/bin/xcrun", arguments: ["simctl", "boot", "sim-id"]),
                RecordedCommand(executable: "/usr/bin/xcrun", arguments: ["simctl", "bootstatus", "sim-id", "-b"]),
                RecordedCommand(executable: "/usr/bin/open", arguments: ["-a", "Simulator"]),
                RecordedCommand(executable: "/usr/bin/xcrun", arguments: ["simctl", "install", "sim-id", actualAppURL.path]),
                RecordedCommand(executable: "/usr/bin/xcrun", arguments: ["simctl", "launch", "sim-id", "com.example.app"]),
            ]
        )
    }

    func testReadsBuiltApplicationURLFromXcodeBuildSettings() throws {
        let data = Data(
            """
            [
              {
                "target": "Support",
                "buildSettings": {
                  "FULL_PRODUCT_NAME": "Support.framework",
                  "TARGET_BUILD_DIR": "/tmp/Products"
                }
              },
              {
                "target": "ActualApp",
                "buildSettings": {
                  "FULL_PRODUCT_NAME": "ActualApp.app",
                  "TARGET_BUILD_DIR": "/tmp/Products"
                }
              }
            ]
            """.utf8
        )

        let url = try XcodeProjectLauncher.builtProductURL(fromBuildSettings: data)

        XCTAssertEqual(url.path, "/tmp/Products/ActualApp.app")
    }

    func testPrefersSchemeTargetWhenBuildSettingsContainMultipleApplications() throws {
        let data = Data(
            """
            [
              {
                "target": "DependencyApp",
                "buildSettings": {
                  "FULL_PRODUCT_NAME": "Dependency.app",
                  "TARGET_BUILD_DIR": "/tmp/Products"
                }
              },
              {
                "target": "DesktopScheme",
                "buildSettings": {
                  "FULL_PRODUCT_NAME": "ActualDesktop.app",
                  "TARGET_BUILD_DIR": "/tmp/Products"
                }
              }
            ]
            """.utf8
        )

        let url = try XcodeProjectLauncher.builtProductURL(
            fromBuildSettings: data,
            preferredTargetName: "DesktopScheme"
        )

        XCTAssertEqual(url.path, "/tmp/Products/ActualDesktop.app")
    }
}

private struct RecordedCommand: Equatable {
    let executable: String
    let arguments: [String]
}

private final class CommandBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [RecordedCommand] = []

    var values: [RecordedCommand] {
        lock.withLock { storage }
    }

    func append(_ value: RecordedCommand) {
        lock.withLock { storage.append(value) }
    }
}

private final class LaunchResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Result<URL, Error>?

    var value: Result<URL, Error>? {
        lock.withLock { storage }
    }

    func set(_ value: Result<URL, Error>) {
        lock.withLock { storage = value }
    }
}

private final class URLBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: URL?

    var value: URL? {
        lock.withLock { storage }
    }

    func set(_ value: URL) {
        lock.withLock { storage = value }
    }
}

private final class MacApplicationFixture: @unchecked Sendable {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("XPlayRestart.\(UUID().uuidString)")
    let bundleIdentifier = "de.mobilepur.XPlayTests.Fixture.\(UUID().uuidString)"
    var appURL: URL { directory.appendingPathComponent("Fixture.app") }
    var markerURL: URL { directory.appendingPathComponent("version.txt") }
    var quitMarkerURL: URL { directory.appendingPathComponent("quit.txt") }
    var plan: XcodeProjectLaunchPlan {
        XcodeProjectLaunchPlan(
            containerURL: directory.appendingPathComponent("Fixture.xcodeproj"),
            containerKind: .project,
            scheme: "Fixture",
            destination: XcodeDestination(platform: .macOS, id: "mac", name: "My Mac"),
            derivedDataURL: directory.appendingPathComponent("DerivedData"),
            logURL: directory.appendingPathComponent("build.log"),
            productName: "Fixture"
        )
    }

    init() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: plan.containerURL, withIntermediateDirectories: true)
    }

    func build(version: String, refusesTermination: Bool = false) throws {
        let executableDirectory = appURL.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: executableDirectory, withIntermediateDirectories: true)
        let source = """
        #import <Cocoa/Cocoa.h>
        @interface FixtureDelegate : NSObject <NSApplicationDelegate>
        @end
        @implementation FixtureDelegate
        - (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
            [@"requested" writeToFile:@"\(quitMarkerURL.path)" atomically:YES encoding:NSUTF8StringEncoding error:nil];
            return \(refusesTermination ? "NSTerminateCancel" : "NSTerminateNow");
        }
        @end
        int main(void) {
            @autoreleasepool {
                NSApplication *app = [NSApplication sharedApplication];
                [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
                FixtureDelegate *delegate = [FixtureDelegate new];
                [app setDelegate:delegate];
                [@"\(version)" writeToFile:@"\(markerURL.path)" atomically:YES encoding:NSUTF8StringEncoding error:nil];
                [app run];
            }
        }
        """
        let sourceURL = directory.appendingPathComponent("main.m")
        try source.write(to: sourceURL, atomically: true, encoding: .utf8)
        let nextExecutable = directory.appendingPathComponent("NextFixture")
        let compiler = Process()
        compiler.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        compiler.arguments = ["clang", "-framework", "Cocoa", sourceURL.path, "-o", nextExecutable.path]
        try compiler.run()
        compiler.waitUntilExit()
        guard compiler.terminationStatus == 0 else {
            throw NSError(domain: "FixtureCompilation", code: Int(compiler.terminationStatus))
        }
        let executable = executableDirectory.appendingPathComponent("Fixture")
        if FileManager.default.fileExists(atPath: executable.path) {
            try FileManager.default.removeItem(at: executable)
        }
        try FileManager.default.moveItem(at: nextExecutable, to: executable)
        let info: NSDictionary = [
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleExecutable": "Fixture",
            "CFBundleName": "XPlay Test Fixture",
            "CFBundlePackageType": "APPL",
            "LSUIElement": true,
        ]
        XCTAssertTrue(info.write(to: appURL.appendingPathComponent("Contents/Info.plist"), atomically: true))
    }

    func cleanUp() {
        for app in NSWorkspace.shared.runningApplications
        where app.bundleURL?.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
            == directory.resolvingSymlinksInPath().standardizedFileURL {
            app.forceTerminate()
        }
        try? FileManager.default.removeItem(at: directory)
    }
}
