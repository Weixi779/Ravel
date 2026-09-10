// Created by weixi on 2026/09/12.

import AppKit
import SwiftUI

public extension Color {
    /// Creates an sRGB color from the low 24 bits (0xRRGGBB), with separate alpha.
    init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(nsColor: NSColor(hex: hex, alpha: alpha))
    }

    /// Accepts six hexadecimal digits, optionally prefixed with `#`.
    /// Invalid input returns nil. Alpha is supplied separately.
    init?(hex: String, alpha: CGFloat = 1) {
        guard let color = NSColor(hex: hex, alpha: alpha) else { return nil }
        self.init(nsColor: color)
    }
}
