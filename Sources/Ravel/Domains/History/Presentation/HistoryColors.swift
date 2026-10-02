//
//  HistoryColors.swift
//  Ravel
//
//  Created by weixi on 2026/09/18.
//  Copyright © 2026 Ravel contributors. All rights reserved.
//  SPDX-License-Identifier: Apache-2.0
//

import AppKit
import DesignSystem

/// Color roles for the history surface. Each appearance supplies resolved colors;
/// cells never derive hierarchy by applying an opacity to an entire row.
enum HistoryColors {
    static let background = color(light: 0xFFFFFF, dark: 0x202226)
    static let title = color(light: 0x252B34, dark: 0xECEEF3)
    static let contextTitle = color(light: 0xA8AAAE, dark: 0x72747A, contrastLight: 0x626871, contrastDark: 0xB4B9C2)
    static let metadata = color(light: 0x737B86, dark: 0x929BA9)
    static let selection = color(light: 0xEDF0F5, dark: 0x303641)
    static let inactiveSelection = color(light: 0xF3F4F7, dark: 0x2A2E35)
    static let conflict = NSColor.systemOrange
    static let divergent = NSColor.systemPurple

    struct PathColors {
        let foreground: NSColor
        let context: NSColor
    }

    private static let paths: [PathColors] = [
        .init(foreground: color(light: 0xA47608, dark: 0xE5BD60), context: color(light: 0xDBC89C, dark: 0x6F603D, contrastLight: 0x93712D, contrastDark: 0xB59955)),
        .init(foreground: color(light: 0x8350B4, dark: 0xC2A0E7), context: color(light: 0xCDB9E1, dark: 0x615472, contrastLight: 0x9064B6, contrastDark: 0xA88CC5)),
        .init(foreground: color(light: 0x3278AD, dark: 0x82BBDF), context: color(light: 0xADC9DE, dark: 0x476070, contrastLight: 0x4D7EAA, contrastDark: 0x78A3C1)),
        .init(foreground: color(light: 0x228078, dark: 0x7BC6BC), context: color(light: 0xA7CCC9, dark: 0x44645F, contrastLight: 0x438C84, contrastDark: 0x70A79F)),
        .init(foreground: color(light: 0xB04F7D, dark: 0xDC93B5), context: color(light: 0xDFB9CB, dark: 0x6B4F5F, contrastLight: 0xA66483, contrastDark: 0xBB819D)),
        .init(foreground: color(light: 0x526473, dark: 0xA6B6C5), context: color(light: 0xBAC1C7, dark: 0x565D66, contrastLight: 0x697784, contrastDark: 0x91A0AF)),
    ]

    static func path(_ identity: Int, focused: Bool) -> NSColor {
        let colors = paths[identity % paths.count]
        return focused ? colors.foreground : colors.context
    }

    private static func color(light: UInt32, dark: UInt32, contrastLight: UInt32? = nil, contrastDark: UInt32? = nil) -> NSColor {
        NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua]) {
            case .darkAqua: NSColor(hex: dark)
            case .accessibilityHighContrastAqua: NSColor(hex: contrastLight ?? light)
            case .accessibilityHighContrastDarkAqua: NSColor(hex: contrastDark ?? dark)
            default: NSColor(hex: light)
            }
        }
    }
}
