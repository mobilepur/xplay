import Foundation
import XCTest
@testable import XPlay

final class XcodeProjectLauncherTests: XCTestCase {
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
