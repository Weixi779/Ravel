// Created by weixi on 2026/09/18.

import AppKit
import SwiftUI

/// Shared semantic colors for changes; warning remains distinct from modification.
public enum ChangeTone: Sendable {
    case addition, deletion, modification, movement, conflict

    public var nsColor: NSColor {
        switch self {
        case .addition: .systemGreen
        case .deletion: .systemRed
        case .modification: .systemBlue
        case .movement: .systemPurple
        case .conflict: .systemOrange
        }
    }

    public var color: Color {
        Color(nsColor: nsColor)
    }

    public var background: NSColor {
        nsColor.withAlphaComponent(0.13)
    }

    public var emphasisBackground: NSColor {
        nsColor.withAlphaComponent(0.27)
    }
}
