//
//  TestSupport.swift
//  Ravel
//
//  Created by weixi on 2026/09/17.
//  Copyright © 2026 Ravel contributors. All rights reserved.
//  SPDX-License-Identifier: Apache-2.0
//

import Foundation
import Testing

nonisolated struct TestFailure: LocalizedError {
    let errorDescription: String?
    init(_ message: String) {
        errorDescription = message
    }
}

/// jj is a fixture builder and independent oracle only. Application reads use
/// the Rust bridge. Files avoid pipe backpressure when a fixture emits much data.
@concurrent
nonisolated func runJJ(_ arguments: [String], at directory: URL) async throws -> String {
    try Task.checkCancellation()
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("Ravel-command-\(UUID())")
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let stdout = temporary.appendingPathComponent("stdout")
    let stderr = temporary.appendingPathComponent("stderr")
    try Data().write(to: stdout)
    try Data().write(to: stderr)
    let output = try FileHandle(forWritingTo: stdout)
    let error = try FileHandle(forWritingTo: stderr)
    defer { try? output.close(); try? error.close() }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/jj")
    process.arguments = ["--no-pager", "--color=never"] + arguments
    process.currentDirectoryURL = directory
    process.standardOutput = output
    process.standardError = error
    try process.run()
    process.waitUntilExit()
    let diagnostic = try String(contentsOf: stderr, encoding: .utf8)
    try #require(process.terminationStatus == 0, "\(diagnostic)")
    try Task.checkCancellation()
    return try String(contentsOf: stdout, encoding: .utf8)
}
