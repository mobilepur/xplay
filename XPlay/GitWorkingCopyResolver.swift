import Darwin
import Foundation

struct GitWorkingCopy: Equatable, Sendable, Identifiable {
    let id: String
    let branchName: String?
    let head: String
    let rootURL: URL?
    let containerURL: URL?
    let lastActivity: Date
    let isDirty: Bool
    let isMainWorktree: Bool

    var displayName: String { branchName ?? "Detached \(head.prefix(7))" }
}

struct GitRepositoryState: Equatable, Sendable {
    let rootURL: URL
    let workingCopies: [GitWorkingCopy]
}

protocol GitWorkingCopyResolving: Sendable {
    func discover(containerURL: URL) throws -> GitRepositoryState?
    func prepare(_ copy: GitWorkingCopy, for containerURL: URL, worktreesDirectory: URL) throws -> URL
}

final class GitWorkingCopyResolver: GitWorkingCopyResolving, @unchecked Sendable {
    enum ResolverError: LocalizedError {
        case gitFailed(String)
        case timedOut
        case staleSelection
        case containerMissing

        var errorDescription: String? {
            switch self {
            case let .gitFailed(message): return "Git could not read or prepare the working copy. \(message)"
            case .timedOut: return "Git took too long. Try refreshing the working copies."
            case .staleSelection: return "This working copy has changed. Refresh the list and select it again."
            case .containerMissing: return "The selected working copy does not contain this Xcode project or workspace."
            }
        }
    }

    private struct Worktree {
        let root: URL
        let head: String
        let branch: String?
    }

    func discover(containerURL: URL) throws -> GitRepositoryState? {
        let sourceDirectory = containerURL.deletingLastPathComponent()
        let rootResult = try run(["rev-parse", "--show-toplevel"], at: sourceDirectory)
        guard rootResult.status == 0 else {
            if rootResult.error.contains("not a git repository") { return nil }
            throw ResolverError.gitFailed(rootResult.error)
        }
        let sourceRoot = canonical(URL(fileURLWithPath: rootResult.output.trimmingCharacters(in: .newlines)))
        let relativeContainer = try relativePath(containerURL, within: sourceRoot)
        let commonDirectory = try gitCommonDirectory(at: sourceRoot)
        let worktrees = try readWorktrees(at: sourceRoot)
        guard let mainRoot = worktrees.first?.root else { return nil }
        let refs = try checked([
            "for-each-ref", "--format=%(refname)%00%(objectname)%00%(committerdate:unix)", "refs/heads/",
        ], at: sourceRoot)
        var copies: [GitWorkingCopy] = []
        var visited = Set<String>()
        for line in refs.split(separator: "\n") {
            let fields = line.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 3 else { continue }
            let branch = String(fields[0].dropFirst("refs/heads/".count))
            let branchWorktrees = worktrees.filter { $0.branch == branch }.map(Optional.some)
            for worktree in branchWorktrees.isEmpty ? [nil] : branchWorktrees {
                copies.append(try workingCopy(
                    branch: branch,
                    head: fields[1],
                    commitTime: TimeInterval(fields[2]) ?? 0,
                    worktree: worktree,
                    sourceRoot: sourceRoot,
                    commonDirectory: commonDirectory,
                    mainRoot: mainRoot,
                    relativeContainer: relativeContainer
                ))
            }
            visited.insert(branch)
        }
        for worktree in worktrees where worktree.branch == nil || !visited.contains(worktree.branch!) {
            let timestamp = try run(["show", "-s", "--format=%ct", worktree.head], at: sourceRoot)
            copies.append(try workingCopy(
                branch: worktree.branch,
                head: worktree.head,
                commitTime: TimeInterval(timestamp.output.trimmingCharacters(in: .newlines)) ?? 0,
                worktree: worktree,
                sourceRoot: sourceRoot,
                commonDirectory: commonDirectory,
                mainRoot: mainRoot,
                relativeContainer: relativeContainer
            ))
        }
        copies.sort {
            if $0.lastActivity != $1.lastActivity { return $0.lastActivity > $1.lastActivity }
            if $0.displayName != $1.displayName { return $0.displayName < $1.displayName }
            return $0.id < $1.id
        }
        return GitRepositoryState(rootURL: mainRoot, workingCopies: copies)
    }

    func prepare(_ copy: GitWorkingCopy, for containerURL: URL, worktreesDirectory: URL) throws -> URL {
        guard let state = try discover(containerURL: containerURL),
              let current = state.workingCopies.first(where: {
                  $0.id == copy.id || (copy.rootURL == nil && copy.branchName != nil && $0.branchName == copy.branchName)
              }),
              current.head == copy.head, current.branchName == copy.branchName,
              copy.rootURL == nil || copy.rootURL == current.rootURL else {
            throw ResolverError.staleSelection
        }
        if current.rootURL != nil {
            guard let existing = current.containerURL else { throw ResolverError.containerMissing }
            return existing
        }
        guard let branch = current.branchName else { throw ResolverError.staleSelection }
        let sourceRoot = try checked(["rev-parse", "--show-toplevel"], at: containerURL.deletingLastPathComponent())
        let relativeContainer = try relativePath(
            containerURL,
            within: URL(fileURLWithPath: sourceRoot.trimmingCharacters(in: .newlines))
        )
        let tracked = try checked(["ls-tree", "--name-only", "-z", current.head, "--", relativeContainer], at: state.rootURL)
        guard tracked.split(separator: "\0").contains(Substring(relativeContainer)) else {
            throw ResolverError.containerMissing
        }
        let name = branch.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "-" }
        let worktreeRoot = canonical(worktreesDirectory.appendingPathComponent(
            String(name.prefix(40)) + "-" + UUID().uuidString
        ))
        try FileManager.default.createDirectory(at: worktreesDirectory, withIntermediateDirectories: true)
        _ = try checked(["worktree", "add", "--", worktreeRoot.path, branch], at: state.rootURL)
        // Another Git client may have moved the branch while the worktree was created.
        // Leave any created worktree intact and require a refresh instead of switching it.
        guard let refreshed = try discover(containerURL: containerURL)?.workingCopies.first(where: {
                  $0.rootURL == worktreeRoot && $0.branchName == branch
              }),
              refreshed.rootURL == worktreeRoot, refreshed.head == copy.head,
              let prepared = refreshed.containerURL else {
            throw ResolverError.staleSelection
        }
        return prepared
    }

    private func workingCopy(
        branch: String?, head: String, commitTime: TimeInterval,
        worktree: Worktree?, sourceRoot: URL, commonDirectory: URL, mainRoot: URL, relativeContainer: String
    ) throws -> GitWorkingCopy {
        var activity = Date(timeIntervalSince1970: commitTime)
        if let branch, let reflog = try reflogDate("refs/heads/" + branch, at: sourceRoot) {
            activity = max(activity, reflog)
        }
        var container: URL?
        var dirty = false
        if let worktree, FileManager.default.fileExists(atPath: worktree.root.path) {
            let identity = try checked(["rev-parse", "--show-toplevel"], at: worktree.root)
            guard canonical(URL(fileURLWithPath: identity.trimmingCharacters(in: .newlines))) == worktree.root,
                  try gitCommonDirectory(at: worktree.root) == commonDirectory else {
                throw ResolverError.staleSelection
            }
            let mapped = worktree.root.appendingPathComponent(relativeContainer)
            if FileManager.default.fileExists(atPath: mapped.path),
               (try? relativePath(mapped, within: worktree.root)) == relativeContainer {
                container = mapped
            }
            if let reflog = try reflogDate("HEAD", at: worktree.root) { activity = max(activity, reflog) }
            let status = try checked(["status", "--porcelain=v1", "-z", "--untracked-files=all", "--no-renames"], at: worktree.root)
            let entries = status.split(separator: "\0")
            dirty = !entries.isEmpty
            var needsIndexDate = false
            for entry in entries {
                let path = String(entry.dropFirst(3))
                if let date = modificationDate(worktree.root.appendingPathComponent(path)) {
                    activity = max(activity, date)
                } else {
                    needsIndexDate = true
                }
            }
            if needsIndexDate {
                let indexPath = try checked(["rev-parse", "--git-path", "index"], at: worktree.root).trimmingCharacters(in: .newlines)
                let index = indexPath.hasPrefix("/") ? URL(fileURLWithPath: indexPath) : worktree.root.appendingPathComponent(indexPath)
                if let date = modificationDate(index) { activity = max(activity, date) }
            }
        }
        return GitWorkingCopy(
            id: worktree.map { "worktree:" + $0.root.path } ?? "branch:" + (branch ?? head),
            branchName: branch, head: head, rootURL: worktree?.root, containerURL: container,
            lastActivity: activity, isDirty: dirty, isMainWorktree: worktree?.root == mainRoot
        )
    }

    private func reflogDate(_ reference: String, at root: URL) throws -> Date? {
        let result = try run(["reflog", "show", "-1", "--format=%gD", "--date=unix", reference, "--"], at: root)
        guard result.status == 0,
              let start = result.output.range(of: "@{", options: .backwards),
              let end = result.output[start.upperBound...].firstIndex(of: "}"),
              let timestamp = TimeInterval(result.output[start.upperBound..<end]) else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    private func readWorktrees(at root: URL) throws -> [Worktree] {
        let output = try checked(["worktree", "list", "--porcelain", "-z"], at: root)
        var result: [Worktree] = []
        var fields: [String: String] = [:]
        for record in output.split(separator: "\0", omittingEmptySubsequences: false) {
            if record.isEmpty {
                if let path = fields["worktree"], let head = fields["HEAD"] {
                    let branch = fields["branch"].flatMap { $0.hasPrefix("refs/heads/") ? String($0.dropFirst(11)) : nil }
                    result.append(Worktree(root: canonical(URL(fileURLWithPath: path)), head: head, branch: branch))
                }
                fields = [:]
            } else {
                let pair = record.split(separator: " ", maxSplits: 1).map(String.init)
                fields[pair[0]] = pair.count == 2 ? pair[1] : ""
            }
        }
        return result
    }

    private func gitCommonDirectory(at root: URL) throws -> URL {
        let path = try checked(["rev-parse", "--path-format=absolute", "--git-common-dir"], at: root)
        return canonical(URL(fileURLWithPath: path.trimmingCharacters(in: .newlines)))
    }

    private func canonical(_ url: URL) -> URL {
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        // Resolving an existing directory can restore its directory hint on macOS 15.
        // Strip it last so a planned worktree and the created folder compare equally.
        return URL(fileURLWithPath: resolved.path, isDirectory: false)
    }

    private func relativePath(_ url: URL, within root: URL) throws -> String {
        let rootParts = canonical(root).pathComponents
        let parts = canonical(url).pathComponents
        guard parts.count > rootParts.count, Array(parts.prefix(rootParts.count)) == rootParts else {
            throw ResolverError.containerMissing
        }
        return parts.dropFirst(rootParts.count).joined(separator: "/")
    }

    private func modificationDate(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
    }

    private func checked(_ arguments: [String], at root: URL) throws -> String {
        let result = try run(arguments, at: root)
        guard result.status == 0 else { throw ResolverError.gitFailed(result.error) }
        return result.output
    }

    private func run(_ arguments: [String], at root: URL) throws -> (status: Int32, output: String, error: String) {
        // File-backed output cannot deadlock when Git fills stdout and stderr together.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("XPlayGitCommand.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let outputURL = directory.appendingPathComponent("stdout")
        let errorURL = directory.appendingPathComponent("stderr")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: outputURL)
        let error = try FileHandle(forWritingTo: errorURL)
        defer { try? output.close(); try? error.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["--no-optional-locks", "-C", root.path] + arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = error
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["LC_ALL"] = "C"
        process.environment = environment
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        try process.run()
        if finished.wait(timeout: .now() + 30) == .timedOut {
            process.terminate()
            if finished.wait(timeout: .now() + 1) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
            }
            throw ResolverError.timedOut
        }
        return (
            process.terminationStatus,
            String(decoding: try Data(contentsOf: outputURL), as: UTF8.self),
            String(decoding: try Data(contentsOf: errorURL), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
