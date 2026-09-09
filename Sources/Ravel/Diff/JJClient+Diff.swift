// Created by weixi on 2026/09/09.

import Foundation
import Subprocess

extension JJClient {
    static let changedFilesTemplate = #"""
    '{"path":' ++ json(path) ++
    ',"sourcePath":' ++ json(source.path()) ++
    ',"status":' ++ json(status) ++ "}\n"
    """#

    @concurrent
    static func loadDiff(_ request: DiffSession.Request) async throws -> RevisionDiff {
        let executable = try findExecutable(customPath: request.executablePath)
        let result = try await execute(executable, readOptions + [
            "diff", "--revisions", request.commitID, "--template", changedFilesTemplate,
        ], at: request.repositoryURL)
        let decoder = JSONDecoder()
        var files: [ChangedFile] = []
        var paths = Set<String>()
        for line in result.output.utf8.split(separator: 0x0A) {
            try Task.checkCancellation()
            let file = try decoder.decode(ChangedFile.self, from: Data(line))
            guard paths.insert(file.path).inserted else { throw FileDiff.Failure.malformedPatch }
            files.append(file)
        }
        return RevisionDiff(files: files, warning: result.error.isEmpty ? nil : result.error)
    }

    @concurrent
    static func loadFileDiff(_ request: DiffSession.Request, file: ChangedFile) async throws -> FileDiff {
        let executable = try findExecutable(customPath: request.executablePath)
        // An exact fileset prevents quotes, globs and operators in a filename from
        // selecting unrelated files. jj follows rename sources for the target path.
        do {
            let result = try await execute(executable, readOptions + [
                "diff", "--revisions", request.commitID, "--git", "--context", "3",
                "--", "root-file:" + filesetString(file.path),
            ], at: request.repositoryURL, outputLimit: FileDiff.byteLimit)
            return try FileDiff(patch: result.output, warning: result.error.isEmpty ? nil : result.error)
        } catch let error as SubprocessError where error.code == .outputLimitExceeded {
            throw FileDiff.Failure.tooLarge
        }
    }

    static func filesetString(_ string: String) -> String {
        // jj literals don't support JSON's \u escapes.
        var result = "\""
        for scalar in string.unicodeScalars {
            switch scalar.value {
            case 0x22: result += "\\\""
            case 0x5C: result += "\\\\"
            case 0...31, 127: result += String(format: "\\x%02x", scalar.value)
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result + "\""
    }
}
