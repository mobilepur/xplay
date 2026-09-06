import Foundation
import XCTest
@testable import XPlay

final class GitWorkingCopyResolverTests: XCTestCase {
    func testNonRepositoryHasNoWorkingCopies() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertNil(try GitWorkingCopyResolver().discover(containerURL: directory.appendingPathComponent("App.xcodeproj")))
    }

    func testDiscoversLocalBranchesAndDetachedWorktreesWithRelativeContainers() throws {
        let repo = try GitFixture()
        defer { repo.cleanUp() }
        try repo.git(["branch", "feature"])
        let featureRoot = repo.directory.appendingPathComponent("Feature With Spaces")
        try repo.git(["worktree", "add", featureRoot.path, "feature"])
        let detachedRoot = repo.directory.appendingPathComponent("Detached")
        try repo.git(["worktree", "add", "--detach", detachedRoot.path, "HEAD"])
        try repo.git(["branch", "unopened"])
        try repo.git(["tag", "unopened"])
        try repo.git(["update-ref", "refs/remotes/origin/remote-only", "HEAD"])

        let state = try XCTUnwrap(GitWorkingCopyResolver().discover(containerURL: featureRoot.appendingPathComponent(repo.relativeContainer)))

        XCTAssertEqual(state.rootURL.path, repo.root.path)
        XCTAssertFalse(state.rootURL.hasDirectoryPath)
        XCTAssertTrue(state.workingCopies.compactMap(\.rootURL).allSatisfy { !$0.hasDirectoryPath },
                      "Worktree identity must not depend on whether its directory already exists")
        XCTAssertEqual(state.workingCopies.count, 4)
        let main = try XCTUnwrap(state.workingCopies.first { $0.branchName == "main" })
        XCTAssertTrue(main.isMainWorktree)
        XCTAssertEqual(main.containerURL, repo.container)
        let feature = try XCTUnwrap(state.workingCopies.first { $0.branchName == "feature" })
        XCTAssertEqual(feature.containerURL, featureRoot.appendingPathComponent(repo.relativeContainer))
        XCTAssertEqual(feature.rootURL, featureRoot)
        let detached = try XCTUnwrap(state.workingCopies.first { $0.branchName == nil })
        XCTAssertEqual(detached.rootURL, detachedRoot)
        XCTAssertTrue(detached.displayName.hasPrefix("Detached "))
        XCTAssertNotNil(state.workingCopies.first { $0.branchName == "unopened" })
        XCTAssertNil(state.workingCopies.first { $0.branchName == "unopened" }?.rootURL)
    }

    func testDirtyTrackedAndUntrackedActivityOrdersCopiesAndIgnoresIgnoredFiles() throws {
        let repo = try GitFixture()
        defer { repo.cleanUp() }
        try repo.git(["branch", "feature"])
        let featureRoot = repo.directory.appendingPathComponent("Feature")
        try repo.git(["worktree", "add", featureRoot.path, "feature"])
        try "changed".write(to: repo.root.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_100_000_000)], ofItemAtPath: repo.root.appendingPathComponent("tracked.txt").path)
        try "new".write(to: featureRoot.appendingPathComponent("new file.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_200_000_000)], ofItemAtPath: featureRoot.appendingPathComponent("new file.txt").path)
        try "ignored".write(to: repo.root.appendingPathComponent("ignored.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_300_000_000)], ofItemAtPath: repo.root.appendingPathComponent("ignored.txt").path)

        let copies = try XCTUnwrap(GitWorkingCopyResolver().discover(containerURL: repo.container)).workingCopies

        XCTAssertEqual(copies.map(\.branchName), ["feature", "main"])
        XCTAssertTrue(copies.allSatisfy(\.isDirty))
        XCTAssertEqual(copies[0].lastActivity, Date(timeIntervalSince1970: 2_200_000_000))
        XCTAssertEqual(copies[1].lastActivity, Date(timeIntervalSince1970: 2_100_000_000))
    }

    func testReflogAndDeletedFileIndexDatesContributeToActivity() throws {
        let repo = try GitFixture()
        defer { repo.cleanUp() }
        try repo.git(["branch", "recent"], date: "2030-01-01T00:00:00Z")
        let resolver = GitWorkingCopyResolver()
        let initial = try XCTUnwrap(resolver.discover(containerURL: repo.container))
        XCTAssertEqual(initial.workingCopies.first?.branchName, "recent")
        XCTAssertEqual(initial.workingCopies.first?.lastActivity, Date(timeIntervalSince1970: 1_893_456_000))

        try FileManager.default.removeItem(at: repo.root.appendingPathComponent("tracked.txt"))
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_200_000_000)], ofItemAtPath: repo.root.appendingPathComponent(".git/index").path)
        let changed = try XCTUnwrap(resolver.discover(containerURL: repo.container))
        XCTAssertEqual(changed.workingCopies.first?.branchName, "main")
        XCTAssertTrue(changed.workingCopies.first?.isDirty == true)
        XCTAssertEqual(changed.workingCopies.first?.lastActivity, Date(timeIntervalSince1970: 2_200_000_000))
    }

    func testEqualActivityHasStableBranchOrdering() throws {
        let repo = try GitFixture()
        defer { repo.cleanUp() }
        try repo.git(["branch", "z-last"])
        try repo.git(["branch", "a-first"])
        let resolver = GitWorkingCopyResolver()
        let state = try XCTUnwrap(resolver.discover(containerURL: repo.container))
        XCTAssertEqual(state.workingCopies.map(\.branchName), ["a-first", "main", "z-last"])
        XCTAssertEqual(try resolver.discover(containerURL: repo.container), state)
    }

    func testPrepareCreatesBranchWorktreeAndPreservesDirtyMainThenReusesIt() throws {
        let repo = try GitFixture()
        defer { repo.cleanUp() }
        try repo.git(["branch", "feature"])
        try "main advanced".write(to: repo.root.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try repo.git(["commit", "-am", "Advance main"])
        try repo.git(["tag", "feature"])
        try "unsaved work".write(to: repo.root.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        let resolver = GitWorkingCopyResolver()
        let copy = try XCTUnwrap(resolver.discover(containerURL: repo.container)?.workingCopies.first { $0.branchName == "feature" })
        let destination = repo.directory.appendingPathComponent("Managed Worktrees")

        let prepared = try resolver.prepare(copy, for: repo.container, worktreesDirectory: destination)
        let reused = try resolver.prepare(copy, for: repo.container, worktreesDirectory: destination)

        XCTAssertEqual(prepared, reused)
        XCTAssertTrue(FileManager.default.fileExists(atPath: prepared.path))
        XCTAssertTrue(prepared.path.hasPrefix(destination.path + "/"))
        XCTAssertEqual(try String(contentsOf: repo.root.appendingPathComponent("tracked.txt"), encoding: .utf8), "unsaved work")
        XCTAssertEqual(try repo.git(["branch", "--show-current"]), "main")
        XCTAssertEqual(try repo.git(["worktree", "list", "--porcelain"]).components(separatedBy: "worktree ").count - 1, 2)
    }

    func testForcedWorktreesForSameBranchRemainDistinctAndReusable() throws {
        let repo = try GitFixture()
        defer { repo.cleanUp() }
        try repo.git(["branch", "feature"])
        let resolver = GitWorkingCopyResolver()
        let unchecked = try XCTUnwrap(resolver.discover(containerURL: repo.container)?.workingCopies.first { $0.branchName == "feature" })
        let firstRoot = repo.directory.appendingPathComponent("Feature A")
        let secondRoot = repo.directory.appendingPathComponent("Feature B")
        try repo.git(["worktree", "add", firstRoot.path, "feature"])
        try repo.git(["worktree", "add", "--force", secondRoot.path, "feature"])
        try "second copy edit".write(to: secondRoot.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        let state = try XCTUnwrap(resolver.discover(containerURL: repo.container))
        let features = state.workingCopies.filter { $0.branchName == "feature" }
        XCTAssertEqual(features.count, 2)
        XCTAssertEqual(Set(features.map(\.id)).count, 2)
        let first = try XCTUnwrap(features.first { $0.rootURL?.path == firstRoot.path })
        let second = try XCTUnwrap(features.first { $0.rootURL?.path == secondRoot.path })
        XCTAssertFalse(first.isDirty)
        XCTAssertTrue(second.isDirty)
        let managed = repo.directory.appendingPathComponent("Managed")
        XCTAssertEqual(try resolver.prepare(first, for: repo.container, worktreesDirectory: managed), firstRoot.appendingPathComponent(repo.relativeContainer))
        XCTAssertEqual(try resolver.prepare(second, for: repo.container, worktreesDirectory: managed), secondRoot.appendingPathComponent(repo.relativeContainer))
        let reused = try resolver.prepare(unchecked, for: repo.container, worktreesDirectory: managed)
        XCTAssertTrue(features.contains { $0.containerURL == reused })
        XCTAssertFalse(FileManager.default.fileExists(atPath: managed.path))

        try repo.git(["worktree", "remove", firstRoot.path])
        let remaining = try XCTUnwrap(resolver.discover(containerURL: repo.container)?.workingCopies.first { $0.branchName == "feature" })
        XCTAssertEqual(remaining.id, second.id, "A worktree ID must survive another checkout being removed")
        XCTAssertEqual(try resolver.prepare(second, for: repo.container, worktreesDirectory: managed), secondRoot.appendingPathComponent(repo.relativeContainer))
    }

    func testPrepareRejectsChangedBranchHeadAndMissingContainer() throws {
        let repo = try GitFixture()
        defer { repo.cleanUp() }
        try repo.git(["branch", "feature"])
        let resolver = GitWorkingCopyResolver()
        let copy = try XCTUnwrap(resolver.discover(containerURL: repo.container)?.workingCopies.first { $0.branchName == "feature" })
        try "new".write(to: repo.root.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try repo.git(["commit", "-am", "New commit"])
        try repo.git(["branch", "-f", "feature", "HEAD"])
        let destination = repo.directory.appendingPathComponent("Managed")
        XCTAssertThrowsError(try resolver.prepare(copy, for: repo.container, worktreesDirectory: destination))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))

        try repo.git(["checkout", "-b", "without-container"])
        try repo.git(["rm", "-r", "Apps"])
        try repo.git(["commit", "-m", "Remove app"])
        try repo.git(["checkout", "main"])
        let missing = try XCTUnwrap(resolver.discover(containerURL: repo.container)?.workingCopies.first { $0.branchName == "without-container" })
        XCTAssertThrowsError(try resolver.prepare(missing, for: repo.container, worktreesDirectory: destination))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testReplacingLinkedFolderWithAnotherRepositoryIsRejected() throws {
        let repo = try GitFixture()
        defer { repo.cleanUp() }
        try repo.git(["branch", "feature"])
        let root = repo.directory.appendingPathComponent("Feature")
        try repo.git(["worktree", "add", root.path, "feature"])
        let resolver = GitWorkingCopyResolver()
        let copy = try XCTUnwrap(resolver.discover(containerURL: repo.container)?.workingCopies.first { $0.branchName == "feature" })
        try FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(repo.relativeContainer), withIntermediateDirectories: true)
        try repo.git(["-C", root.path, "init", "--initial-branch=feature"])
        XCTAssertThrowsError(try resolver.prepare(copy, for: repo.container, worktreesDirectory: repo.directory.appendingPathComponent("Managed")))
    }

    func testRemovedWorktreeAndChangedCheckoutAreNotSilentlyRecreated() throws {
        let repo = try GitFixture()
        defer { repo.cleanUp() }
        try repo.git(["branch", "feature"])
        let root = repo.directory.appendingPathComponent("Feature")
        try repo.git(["worktree", "add", root.path, "feature"])
        let resolver = GitWorkingCopyResolver()
        let copy = try XCTUnwrap(resolver.discover(containerURL: repo.container)?.workingCopies.first { $0.branchName == "feature" })
        try repo.git(["-C", root.path, "checkout", "--detach"])
        XCTAssertThrowsError(try resolver.prepare(copy, for: repo.container, worktreesDirectory: repo.directory.appendingPathComponent("Managed")))
        try FileManager.default.removeItem(at: root)
        let detached = try XCTUnwrap(resolver.discover(containerURL: repo.container)?.workingCopies.first { $0.branchName == nil })
        XCTAssertNil(detached.containerURL)
        XCTAssertThrowsError(try resolver.prepare(detached, for: repo.container, worktreesDirectory: repo.directory.appendingPathComponent("Managed")))
    }
}

private final class GitFixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("XPlayGit.\(UUID().uuidString)").resolvingSymlinksInPath()
    var root: URL { directory.appendingPathComponent("Repository With Spaces") }
    let relativeContainer = "Apps/Desktop/Sample.xcodeproj"
    var container: URL { root.appendingPathComponent(relativeContainer) }

    init() throws {
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        try "project".write(to: container.appendingPathComponent("project.pbxproj"), atomically: true, encoding: .utf8)
        try "initial".write(to: root.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try "ignored.txt\n".write(to: root.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        try git(["init", "--initial-branch=main"])
        try git(["config", "user.name", "Test"])
        try git(["config", "user.email", "test@example.invalid"])
        try git(["add", "."])
        try git(["commit", "-m", "Initial"])
    }

    @discardableResult
    func git(_ arguments: [String], date: String = "2001-09-09T01:46:40Z") throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", root.path] + arguments
        process.standardOutput = output
        process.standardError = output
        process.environment = ProcessInfo.processInfo.environment.merging([
            "GIT_AUTHOR_DATE": date,
            "GIT_COMMITTER_DATE": date,
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": "/dev/null",
        ]) { _, new in new }
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else { throw NSError(domain: "GitFixture", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: text]) }
        return text
    }

    func cleanUp() { try? FileManager.default.removeItem(at: directory) }
}
