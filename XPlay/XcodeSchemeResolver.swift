import Foundation

final class XcodeSchemeResolver: @unchecked Sendable {
    struct ProcessResult {
        let status: Int32
        let output: Data
        let diagnostic: Data
    }

    private final class DataBox: @unchecked Sendable {
        var data = Data()
    }

    enum ResolverError: LocalizedError {
        case xcodebuildFailed(status: Int32, message: String)

        var errorDescription: String? {
            switch self {
            case let .xcodebuildFailed(status, message):
                let detail = message.isEmpty ? "No diagnostic output was produced." : message
                return "Could not read project schemes (xcodebuild status \(status)). \(detail)"
            }
        }
    }

    typealias CommandRunner = ([String]) throws -> Data

    private struct Listing: Decodable {
        struct Container: Decodable {
            let schemes: [String]?
        }

        let project: Container?
        let workspace: Container?
    }

    private let runCommand: CommandRunner

    convenience init() {
        self.init(runCommand: Self.runXcodebuild)
    }

    init(runCommand: @escaping CommandRunner) {
        self.runCommand = runCommand
    }

    func schemes(for containerURL: URL, kind: XcodeContainerKind) throws -> [String] {
        let data = try runCommand([
            "-list",
            "-json",
            kind.xcodebuildArgument,
            containerURL.standardizedFileURL.path,
        ])
        let listing = try JSONDecoder().decode(Listing.self, from: data)
        switch kind {
        case .project:
            return listing.project?.schemes ?? []
        case .workspace:
            return listing.workspace?.schemes ?? []
        }
    }

    func schemes(for projectURL: URL) throws -> [String] {
        try schemes(
            for: projectURL,
            kind: projectURL.pathExtension.lowercased() == "xcworkspace" ? .workspace : .project
        )
    }

    func destinations(
        for containerURL: URL,
        kind: XcodeContainerKind,
        scheme: String
    ) throws -> [XcodeDestination] {
        let data = try runCommand([
            "-showdestinations",
            kind.xcodebuildArgument,
            containerURL.standardizedFileURL.path,
            "-scheme",
            scheme,
        ])
        return Self.parseDestinations(String(decoding: data, as: UTF8.self))
    }

    private static func parseDestinations(_ output: String) -> [XcodeDestination] {
        var isIneligibleSection = false
        return output
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> XcodeDestination? in
                let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if text.hasPrefix("Ineligible destinations") {
                    isIneligibleSection = true
                } else if text.hasPrefix("Available destinations") {
                    isIneligibleSection = false
                }
                guard
                    !isIneligibleSection,
                    text.hasPrefix("{"), text.hasSuffix("}"),
                    !text.contains("variant:"),
                    field("error", in: text) == nil
                else {
                    return nil
                }
                guard
                    let platformValue = field("platform", in: text),
                    let id = field("id", in: text),
                    let name = field("name", in: text),
                    !id.localizedCaseInsensitiveContains("placeholder")
                else {
                    return nil
                }

                let platform: XcodeDestination.Platform
                switch platformValue {
                case "macOS":
                    platform = .macOS
                case "iOS Simulator":
                    platform = .iOSSimulator
                default:
                    return nil
                }

                return XcodeDestination(
                    platform: platform,
                    id: id,
                    name: name,
                    osVersion: field("OS", in: text)
                )
            }
            .reduce(into: [XcodeDestination]()) { result, destination in
                if !result.contains(where: {
                    $0.platform == destination.platform && $0.id == destination.id
                }) {
                    result.append(destination)
                }
            }
    }

    private static func field(_ key: String, in text: String) -> String? {
        let escapedKey = NSRegularExpression.escapedPattern(for: key)
        guard let expression = try? NSRegularExpression(
            pattern: "(?:^\\s*\\{\\s*|,\\s*)\(escapedKey):([^,}]*)"
        ) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard
            let match = expression.firstMatch(in: text, range: range),
            let valueRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        let value = text[valueRange].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func runXcodebuild(arguments: [String]) throws -> Data {
        let result = try runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/xcodebuild"),
            arguments: arguments
        )

        guard result.status == 0 else {
            throw ResolverError.xcodebuildFailed(
                status: result.status,
                message: String(data: result.diagnostic, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            )
        }
        return result.output
    }

    static func runProcess(
        executableURL: URL,
        arguments: [String]
    ) throws -> ProcessResult {
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        let output = DataBox()
        let diagnostic = DataBox()
        let readers = DispatchGroup()
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
        process.waitUntilExit()
        readers.wait()

        return ProcessResult(
            status: process.terminationStatus,
            output: output.data,
            diagnostic: diagnostic.data
        )
    }
}
