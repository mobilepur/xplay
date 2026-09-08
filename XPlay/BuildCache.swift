import AppKit
import Darwin
import Foundation
import OSLog

/// Owns only XPlay's disposable build data, never project sources or worktrees.
final class BuildCache: @unchecked Sendable {
    static let defaultDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("XPlay", isDirectory: true)
    static let shared = BuildCache(directory: defaultDirectory)

    private static let logger = Logger(subsystem: "de.mobilepur.XPlay", category: "BuildCache")
    private static let lastUseName = ".xplay-last-used"
    private let directory: URL
    private let maximumBytes: Int64
    private let maximumAge: TimeInterval
    private let now: () -> Date
    private let runningApplicationURLs: () -> [URL]
    private let queue = DispatchQueue(label: "de.mobilepur.XPlay.cache-cleanup", qos: .utility)
    private let fileManager = FileManager.default

    init(
        directory: URL,
        maximumBytes: Int64 = 5_000_000_000,
        maximumAge: TimeInterval = 7 * 24 * 60 * 60,
        now: @escaping () -> Date = Date.init,
        runningApplicationURLs: @escaping () -> [URL] = {
            NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }.compactMap(\.bundleURL)
        }
    ) {
        self.directory = directory.standardizedFileURL
        self.maximumBytes = maximumBytes
        self.maximumAge = maximumAge
        self.now = now
        self.runningApplicationURLs = runningApplicationURLs
    }

    /// The shared file lock spans building, product resolution and app launch.
    /// An exclusive cleanup lock also protects builds in other XPlay processes.
    final class Lease: @unchecked Sendable {
        private let lock = NSLock()
        private var descriptor: Int32?
        private let cache: BuildCache
        private let url: URL

        fileprivate init(descriptor: Int32, cache: BuildCache, url: URL) {
            self.descriptor = descriptor
            self.cache = cache
            self.url = url
        }

        func finish() {
            lock.withLock {
                guard let descriptor else { return }
                cache.recordUse(of: url)
                flock(descriptor, LOCK_UN)
                close(descriptor)
                self.descriptor = nil
                cache.cleanUp()
            }
        }

        deinit { finish() }
    }

    func beginUsing(_ url: URL) throws -> Lease {
        let root = directory.appendingPathComponent("DerivedData", isDirectory: true)
        guard url.standardizedFileURL.deletingLastPathComponent() == root.standardizedFileURL else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let descriptor = try openLock()
        guard flock(descriptor, LOCK_SH) == 0 else {
            let error = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            close(descriptor)
            throw error
        }
        do {
            try ensureDirectory(root)
            try ensureDirectory(url)
            recordUse(of: url)
            return Lease(descriptor: descriptor, cache: self, url: url)
        } catch {
            flock(descriptor, LOCK_UN)
            close(descriptor)
            throw error
        }
    }

    func cleanUp() {
        queue.async { self.performCleanup() }
    }

    /// Also lets callers wait for previously scheduled cleanup without timing sleeps.
    func cleanUpNow() {
        queue.sync { performCleanup() }
    }

    private func openLock() throws -> Int32 {
        try ensureDirectory(directory)
        let descriptor = open(directory.appendingPathComponent(".build-cache.lock").path,
                              O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        return descriptor
    }

    private func ensureDirectory(_ url: URL) throws {
        if let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]), values.isSymbolicLink == true {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func recordUse(of url: URL) {
        let marker = url.appendingPathComponent(Self.lastUseName)
        do {
            // Atomic replacement avoids following a pre-existing symlink.
            try Data().write(to: marker, options: .atomic)
            try fileManager.setAttributes([.modificationDate: now()], ofItemAtPath: marker.path)
        } catch {
            Self.logger.error("Could not record build cache use: \(error.localizedDescription)")
        }
    }

    private struct Entry {
        let url: URL
        let lastUse: Date
        let bytes: Int64
    }

    private func performCleanup() {
        do {
            let descriptor = try openLock()
            defer { close(descriptor) }
            guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { return }
            defer { flock(descriptor, LOCK_UN) }

            let root = directory.appendingPathComponent("DerivedData", isDirectory: true)
            guard isPlainDirectory(root) else { return }
            let children = try fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            let entries = children.compactMap(inspect).sorted {
                $0.lastUse == $1.lastUse ? $0.url.path < $1.url.path : $0.lastUse < $1.lastUse
            }
            let cutoff = now().addingTimeInterval(-maximumAge)
            var totalBytes = entries.reduce(Int64(0)) { $0 + $1.bytes }
            let newestURL = entries.last?.url
            for entry in entries {
                let expired = entry.lastUse < cutoff
                let overBudget = totalBytes > maximumBytes && entry.url != newestURL
                guard expired || overBudget, !containsRunningApplication(entry.url) else { continue }
                do {
                    try fileManager.removeItem(at: entry.url)
                    totalBytes -= entry.bytes
                } catch {
                    Self.logger.error("Could not remove build cache: \(error.localizedDescription)")
                }
            }
            removeExpiredLogs(before: cutoff)
        } catch {
            Self.logger.error("Build cache cleanup skipped: \(error.localizedDescription)")
        }
    }

    private func isPlainDirectory(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else {
            return false
        }
        return values.isDirectory == true && values.isSymbolicLink != true
    }

    private func inspect(_ url: URL) -> Entry? {
        guard isPlainDirectory(url) else { return nil }
        let keys: Set<URLResourceKey> = [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        var readable = true
        guard let enumerator = fileManager.enumerator(
            at: url, includingPropertiesForKeys: Array(keys),
            errorHandler: { _, _ in readable = false; return false }
        ) else { return nil }
        do {
            var lastUse = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantFuture
            var bytes: Int64 = 0
            for case let child as URL in enumerator {
                let values = try child.resourceValues(forKeys: keys)
                if values.isSymbolicLink == true {
                    enumerator.skipDescendants()
                    continue
                }
                if let date = values.contentModificationDate { lastUse = max(lastUse, date) }
                if values.isRegularFile == true { bytes += Int64(values.fileSize ?? 0) }
            }
            guard readable else { return nil }
            return Entry(url: url, lastUse: lastUse, bytes: bytes)
        } catch {
            // Incomplete scans must never make a cache look older or smaller.
            return nil
        }
    }

    private func containsRunningApplication(_ url: URL) -> Bool {
        let prefix = url.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        return runningApplicationURLs().contains {
            $0.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(prefix)
        }
    }

    private func removeExpiredLogs(before cutoff: Date) {
        let logs = directory.appendingPathComponent("Logs", isDirectory: true)
        guard isPlainDirectory(logs),
              let files = try? fileManager.contentsOfDirectory(at: logs, includingPropertiesForKeys: nil)
        else { return }
        for url in files where url.pathExtension == "log" {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true,
                  let date = values.contentModificationDate, date < cutoff
            else { continue }
            do {
                try fileManager.removeItem(at: url)
            } catch {
                Self.logger.error("Could not remove expired build log: \(error.localizedDescription)")
            }
        }
    }
}
