// Created by weixi on 2026/09/12.

import AppKit

public extension NSColor {
    /// Creates an sRGB color from the low 24 bits (0xRRGGBB), with separate alpha.
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha,
        )
    }

    /// Accepts six hexadecimal digits, optionally prefixed with `#`.
    /// Invalid input returns nil. Alpha is supplied separately.
    convenience init?(hex: String, alpha: CGFloat = 1) {
        let digits = hex.hasPrefix("#") ? hex.dropFirst() : hex[...]
        guard digits.utf8.count == 6,
              digits.utf8.allSatisfy({
                  (48 ... 57).contains($0) || (65 ... 70).contains($0) || (97 ... 102).contains($0)
              }),
              let value = UInt32(digits, radix: 16) else { return nil }
        self.init(hex: value, alpha: alpha)
    }
}
