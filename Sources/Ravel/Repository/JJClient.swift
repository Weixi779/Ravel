// Created by weixi on 2026/09/09.

import Foundation
import Logger
import Subprocess

nonisolated struct JJClient: Sendable {
    private static let logger = Logger.make(category: "JJClient")
    static func readOptions(at operationID: String?) -> [String] {
        ["--no-pager", "--color=never", "--ignore-working-copy", "--at-op=" + (operationID ?? "@")]
    }

    enum Failure: Error, Sendable {
        case executableNotFound
        case invalidExecutable(String)
        case unsupportedVersion(String)
        case commandFailed(String)
        case commandExited(String)
    }

    static func checkedExecutable(at directory: URL, customPath: String?) async throws -> String {
        let executable = try findExecutable(customPath: customPath)
        let version = try await execute(executable, ["--version"], at: directory).output
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard supportsVersion(version) else { throw Failure.unsupportedVersion(version) }
        return executable
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
        let command = arguments.first { ["--version", "diff"].contains($0) } ?? "other"
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
