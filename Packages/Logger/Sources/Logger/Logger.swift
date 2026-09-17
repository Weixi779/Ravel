// Created by weixi on 2026/09/12.

public import os
import Foundation

/// Creates native loggers in the host application's unified logging subsystem.
public enum Logger {
    /// No application setup is required. Native interpolation, privacy, and levels
    /// remain available directly on the returned logger.
    public static func make(category: String) -> os.Logger {
        os.Logger(subsystem: Bundle.main.bundleIdentifier ?? "Logger", category: category)
    }
}
