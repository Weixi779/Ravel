// Created by weixi on 2026/09/09.

import Foundation
import Logger
import Subprocess

nonisolated struct JJClient: Sendable {
    private static let logger = Logger.make(category: "JJClient")
    static let revisionLimit = 300
    static let readOptions = ["--no-pager", "--color=never", "--ignore-working-copy", "--at-op=@"]

    enum Failure: Error, Sendable {
        case executableNotFound
        case invalidExecutable(String)
        case invalidDirectory(String)
        case unsupportedVersion(String)
        case commandFailed(String)
        case commandExited(String)
        case malformedOutput(Int)
        case duplicateCommit
    }

    // Explicit fields form Ravel's wire format. Each value is escaped by jj,
    // including multiline descriptions and bookmark names.
    static let logTemplate = #"""
    '{' ++
    '"commitID":' ++ json(commit_id) ++ ',' ++
    '"changeID":' ++ json(change_id) ++ ',' ++
    '"parentIDs":' ++ json(parents.map(|p| p.commit_id())) ++ ',' ++
    '"description":' ++ json(description) ++ ',' ++
    '"author":' ++ json(author.name()) ++ ',' ++
    '"email":' ++ json(stringify(author.email())) ++ ',' ++
    '"timestamp":' ++ json(committer.timestamp().utc().format("%Y-%m-%dT%H:%M:%SZ")) ++ ',' ++
    '"bookmarks":' ++ json(bookmarks.map(|b| stringify(b))) ++ ',' ++
    '"isWorkingCopy":' ++ json(current_working_copy) ++ ',' ++
    '"isImmutable":' ++ json(immutable) ++ ',' ++
    '"hasConflict":' ++ json(conflict) ++ ',' ++
    '"isDivergent":' ++ json(divergent) ++ ',' ++
    '"isEmpty":' ++ json(empty) ++ "}\n"
    """#

    @concurrent
    static func loadLog(at directory: URL, executablePath: String?) async throws -> RepositoryLog {
        try Task.checkCancellation()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw Failure.invalidDirectory(directory.path)
        }

        let executable = try findExecutable(customPath: executablePath)
        let version = try await execute(executable, ["--version"], at: directory).output
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard supportsVersion(version) else { throw Failure.unsupportedVersion(version) }

        let rootOutput = try await execute(executable, readOptions + ["root"], at: directory).output
        // `root` appends one newline; a directory name may itself contain whitespace.
        let rootPath = rootOutput.hasSuffix("\n") ? String(rootOutput.dropLast()) : rootOutput
        let root = URL(fileURLWithPath: rootPath, isDirectory: true)
        let output = try await execute(executable, readOptions + [
            "log", "--no-graph", "--limit", String(revisionLimit + 1), "--template", logTemplate,
        ], at: root)
        try Task.checkCancellation()
        let decoded = try decodeLog(Data(output.output.utf8))
        let revisions = Array(decoded.prefix(revisionLimit))
        return try RepositoryLog(
            repositoryURL: root,
            revisions: revisions,
            graph: LogGraph(revisions: revisions),
            isLimited: decoded.count > revisionLimit,
            jjVersion: version,
            warning: output.error.isEmpty ? nil : output.error
        )
    }

    static func decodeLog(_ data: Data) throws -> [Revision] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var revisions: [Revision] = []
        var seen = Set<String>()
        for (index, line) in data.split(separator: 0x0A).enumerated() {
            try Task.checkCancellation()
            let revision: Revision
            do {
                revision = try decoder.decode(Revision.self, from: Data(line))
            } catch {
                throw Failure.malformedOutput(index + 1)
            }
            guard seen.insert(revision.id).inserted else { throw Failure.duplicateCommit }
            revisions.append(revision)
        }
        return revisions
    }

    static func supportsVersion(_ string: String) -> Bool {
        guard let version = string.split(separator: " ").dropFirst().first else { return false }
        let parts = version.split(separator: ".")
        guard parts.count >= 2, let major = Int(parts[0]), let minor = Int(parts[1]) else { return false }
        return major > 0 || minor >= 41
    }

    static func findExecutable(customPath: String?) throws -> String {
        if let customPath, !customPath.isEmpty {
            guard FileManager.default.isExecutableFile(atPath: customPath) else {
                throw Failure.invalidExecutable(customPath)
            }
            return customPath
        }
        // Finder-launched apps don't inherit an interactive shell's PATH.
        let path = ProcessInfo.processInfo.environment["PATH", default: ""]
        let candidates = ["/opt/homebrew/bin", "/usr/local/bin"] + path.split(separator: ":").map(String.init)
        for directory in candidates where directory.hasPrefix("/") {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent("jj").path
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        throw Failure.executableNotFound
    }

    static func execute(
        _ executable: String,
        _ arguments: [String],
        at directory: URL,
        outputLimit: Int = 16 * 1024 * 1024
    ) async throws -> (output: String, error: String) {
        try Task.checkCancellation()
        let logger = Self.logger
        let invocationID = UUID().uuidString
        // Record only known operation names; arguments can contain paths and file contents.
        let command = arguments.first { ["--version", "root", "log", "diff"].contains($0) } ?? "other"
        let started = ContinuousClock.now
        logger.debug("Command started command=\(command, privacy: .public) invocationID=\(invocationID, privacy: .public)")
        var options = PlatformOptions()
        options.teardownSequence = [.gracefulShutDown(allowedDurationToNextStep: .seconds(1))]
        do {
            let result = try await Subprocess.run(
                .path(.init(executable)),
                arguments: .init(arguments),
                workingDirectory: .init(directory.path),
                platformOptions: options,
                output: .string(limit: outputLimit),
                error: .string(limit: 256 * 1024)
            )
            try Task.checkCancellation()
            logger.debug("""
                Command exited command=\(command, privacy: .public) invocationID=\(invocationID, privacy: .public) \
                status=\(String(describing: result.terminationStatus), privacy: .public) \
                duration=\(String(describing: started.duration(to: .now)), privacy: .public) \
                stdoutBytes=\(result.standardOutput.utf8.count) stderrBytes=\(result.standardError.utf8.count)
                """)
            guard result.terminationStatus.isSuccess else {
                let message = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
                if message.isEmpty { throw Failure.commandExited(String(describing: result.terminationStatus)) }
                throw Failure.commandFailed(message)
            }
            return (result.standardOutput, result.standardError.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            logger.debug("""
                Command interrupted command=\(command, privacy: .public) invocationID=\(invocationID, privacy: .public) \
                cancelled=\(Task.isCancelled) duration=\(String(describing: started.duration(to: .now)), privacy: .public) \
                errorType=\(String(reflecting: type(of: error)), privacy: .public)
                """)
            throw error
        }
    }
}
