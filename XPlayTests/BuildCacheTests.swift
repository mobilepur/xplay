import Foundation
import XCTest
@testable import XPlay

final class BuildCacheTests: XCTestCase {
    private var directory: URL!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86_400

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("XPlayCacheTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testRemovesExpiredCachesAndLogsButPreservesRecentCacheAndOtherFiles() throws {
        let old = try entry("old", age: 8 * day)
        let recent = try entry("recent", age: day)
        let log = try file("Logs/old-build.log", age: 8 * day)
        let other = try file("user-file.txt", age: 8 * day)

        cache().cleanUpNow()

        XCTAssertFalse(exists(old))
        XCTAssertFalse(exists(log))
        XCTAssertTrue(exists(recent))
        XCTAssertTrue(exists(other))
    }

    func testEvictsLeastRecentlyUsedCachesToBudgetAndKeepsNewestEvenIfOversized() throws {
        let oldest = try entry("oldest", age: 3 * day)
        let middle = try entry("middle", age: 2 * day)
        let newest = try entry("newest", age: day)

        cache(maximumBytes: 16).cleanUpNow()

        XCTAssertFalse(exists(oldest))
        XCTAssertTrue(exists(middle))
        XCTAssertTrue(exists(newest))

        cache(maximumBytes: 1).cleanUpNow()
        XCTAssertFalse(exists(middle))
        XCTAssertTrue(exists(newest))
    }

    func testRunningApplicationProtectsEntireLegacyCache() throws {
        let old = try entry("Earnie", age: 8 * day)
        let app = old.appendingPathComponent("Earnie-macOS/Build/Products/Debug/Earnie.app")
        cache(maximumBytes: 1, runningApps: [app]).cleanUpNow()
        XCTAssertTrue(exists(old))
    }

    func testLegacyCacheUsesNewestDescendantDate() throws {
        let legacy = try entry("Earnie", age: 8 * day)
        _ = try file("DerivedData/Earnie/iOS/Build/product", age: day)
        try setDate(legacy, age: 8 * day)
        cache().cleanUpNow()
        XCTAssertTrue(exists(legacy))
    }

    func testBuildLeaseBlocksOtherCleanerAndRefreshesLastUse() throws {
        let old = try entry("old", age: 8 * day)
        let active = try entry("active", age: 8 * day)
        let owner = cache()
        let lease = try owner.beginUsing(active)

        cache().cleanUpNow()
        XCTAssertTrue(exists(old), "Cleanup must wait until every build/launch finishes")
        XCTAssertTrue(exists(active))

        lease.finish()
        owner.cleanUpNow()
        XCTAssertFalse(exists(old))
        XCTAssertTrue(exists(active), "Last use must be refreshed even after a failed build")
    }

    func testSymlinkEntryAndSymlinkDerivedDataRootAreNeverFollowed() throws {
        let outside = directory.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let sentinel = try file("outside/keep", age: 8 * day)
        let root = directory.appendingPathComponent("DerivedData")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("linked"), withDestinationURL: outside)
        cache(maximumBytes: 0).cleanUpNow()
        XCTAssertTrue(exists(sentinel))
        XCTAssertTrue(exists(root.appendingPathComponent("linked")))

        try FileManager.default.removeItem(at: root)
        try FileManager.default.createSymbolicLink(at: root, withDestinationURL: outside)
        cache(maximumBytes: 0).cleanUpNow()
        XCTAssertTrue(exists(sentinel))
    }

    func testLauncherKeepsLeaseUntilMacApplicationOpenCompletes() throws {
        let old = try entry("old", age: 8 * day)
        let plan = try launchPlan()
        let owner = cache()
        let opening = expectation(description: "opening application")
        let finished = expectation(description: "launch finished")
        var finishOpening: (@Sendable (Error?) -> Void)?
        let launcher = XcodeProjectLauncher(
            plan: plan, runCommand: { _, _, _, _ in 0 },
            openMacApplication: { _, completion in
                finishOpening = completion
                opening.fulfill()
            },
            resolveBuiltProduct: { _ in plan.builtAppURL }, buildCache: owner
        )

        launcher.launch { result in
            if case let .failure(error) = result { XCTFail("Unexpected error: \(error)") }
            finished.fulfill()
        }
        wait(for: [opening], timeout: 5)
        owner.cleanUpNow()
        XCTAssertTrue(exists(old), "The lease must cover the asynchronous app opener")
        finishOpening?(nil)
        wait(for: [finished], timeout: 5)
        owner.cleanUpNow()
        XCTAssertFalse(exists(old))
        XCTAssertTrue(exists(plan.builtAppURL))
    }

    func testFailedBuildReleasesLeaseAndTriggersCleanup() throws {
        let old = try entry("old", age: 8 * day)
        let plan = try launchPlan()
        let owner = cache()
        let finished = expectation(description: "failed launch finished")
        let launcher = XcodeProjectLauncher(
            plan: plan, runCommand: { _, _, _, _ in 65 },
            openMacApplication: { _, _ in XCTFail("Failed builds must not open apps") },
            buildCache: owner
        )
        launcher.launch { result in
            if case .success = result { XCTFail("Expected build failure") }
            finished.fulfill()
        }
        wait(for: [finished], timeout: 5)
        owner.cleanUpNow()
        XCTAssertFalse(exists(old))
        XCTAssertTrue(exists(plan.derivedDataURL))
    }

    func testCancelledBuildKeepsLeaseUntilCommandExits() throws {
        let old = try entry("old", age: 8 * day)
        let plan = try launchPlan()
        let owner = cache()
        let started = expectation(description: "build started")
        let finished = expectation(description: "cancelled launch finished")
        let exitCommand = DispatchSemaphore(value: 0)
        let launcher = XcodeProjectLauncher(
            plan: plan,
            runCommand: { _, _, _, _ in
                started.fulfill()
                guard exitCommand.wait(timeout: .now() + 5) == .success else {
                    XCTFail("Test did not release the build command")
                    return 1
                }
                return 0
            },
            openMacApplication: { _, _ in XCTFail("Cancelled builds must not open apps") },
            buildCache: owner
        )
        launcher.launch { result in
            if case let .failure(error) = result {
                XCTAssertTrue(error is CancellationError)
            } else {
                XCTFail("Expected cancellation")
            }
            finished.fulfill()
        }
        wait(for: [started], timeout: 5)
        launcher.cancel()
        owner.cleanUpNow()
        XCTAssertTrue(exists(old), "Cancel must not unlock while the build process is still exiting")
        exitCommand.signal()
        wait(for: [finished], timeout: 5)
        owner.cleanUpNow()
        XCTAssertFalse(exists(old))
        XCTAssertTrue(exists(plan.derivedDataURL))
    }

    func testCleanupWaitsForEveryConcurrentLease() throws {
        let old = try entry("old", age: 8 * day)
        let first = try entry("first", age: day)
        let second = try entry("second", age: day)
        let owner = cache()
        let other = cache()
        let firstLease = try owner.beginUsing(first)
        let secondLease = try other.beginUsing(second)
        firstLease.finish()
        owner.cleanUpNow()
        XCTAssertTrue(exists(old))
        secondLease.finish()
        owner.cleanUpNow()
        other.cleanUpNow()
        XCTAssertFalse(exists(old))
        XCTAssertTrue(exists(first))
        XCTAssertTrue(exists(second))
    }

    private func launchPlan() throws -> XcodeProjectLaunchPlan {
        let container = try file("Example.xcodeproj", age: 0)
        let plan = XcodeProjectLaunchPlan(
            containerURL: container, containerKind: .project, scheme: "Example",
            destination: XcodeDestination(platform: .macOS, id: "mac", name: "My Mac"),
            derivedDataURL: directory.appendingPathComponent("DerivedData/current"),
            logURL: directory.appendingPathComponent("Logs/current-build.log"), productName: "Example"
        )
        try FileManager.default.createDirectory(at: plan.builtAppURL, withIntermediateDirectories: true)
        return plan
    }

    private func cache(maximumBytes: Int64 = 1_000_000, runningApps: [URL] = []) -> BuildCache {
        BuildCache(directory: directory, maximumBytes: maximumBytes, maximumAge: 7 * day,
                   now: { self.now }, runningApplicationURLs: { runningApps })
    }

    private func entry(_ name: String, age: TimeInterval) throws -> URL {
        _ = try file("DerivedData/\(name)/payload", age: age)
        let url = directory.appendingPathComponent("DerivedData/\(name)")
        try setDate(url, age: age)
        return url
    }

    @discardableResult
    private func file(_ path: String, age: TimeInterval) throws -> URL {
        let url = directory.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 42, count: 8).write(to: url)
        try setDate(url, age: age)
        return url
    }

    private func setDate(_ url: URL, age: TimeInterval) throws {
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: url.path)
    }

    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
}
