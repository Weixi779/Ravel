//
//  HexColorTests.swift
//  Ravel
//
//  Created by weixi on 2026/09/12.
//  Copyright © 2026 Ravel contributors. All rights reserved.
//  SPDX-License-Identifier: Apache-2.0
//

import AppKit
import DesignSystem
import SwiftUI
import Testing

struct HexColorTests {
    @Test
    func integerPreservesRGBAndAlpha() throws {
        let native = NSColor(hex: 0x12ABEF, alpha: 0.4)
        let bridged = try #require(NSColor(Color(hex: 0x12ABEF, alpha: 0.4)).usingColorSpace(.sRGB))
        for color in [native, bridged] {
            #expect(abs(color.redComponent - 18.0 / 255) < 0.00001)
            #expect(abs(color.greenComponent - 171.0 / 255) < 0.00001)
            #expect(abs(color.blueComponent - 239.0 / 255) < 0.00001)
            #expect(abs(color.alphaComponent - 0.4) < 0.00001)
        }
    }

    @Test(arguments: ["12ABEF", "#12ABEF", "12abef", "#12AbEf"])
    func stringAcceptsOptionalPrefixAndMixedCase(_ input: String) throws {
        let native = try #require(NSColor(hex: input, alpha: 0.4))
        let swiftUI = try #require(Color(hex: input, alpha: 0.4))
        #expect(native == NSColor(hex: 0x12ABEF, alpha: 0.4))
        #expect(swiftUI == Color(hex: 0x12ABEF, alpha: 0.4))
    }

    @Test(arguments: ["", "#", "FFF", "#12345678", "GG1234", "+12345", " 123456", "123456\n", "##123456"])
    func stringRejectsMalformedInput(_ input: String) {
        #expect(NSColor(hex: input) == nil)
        #expect(Color(hex: input) == nil)
    }

    @Test
    func colorsDefaultToOpaque() throws {
        #expect(NSColor(hex: 0).alphaComponent == 1)
        #expect(try #require(NSColor(hex: "#FFFFFF")).alphaComponent == 1)
        let color = try #require(NSColor(Color(hex: 0xFFFFFF)).usingColorSpace(.sRGB))
        #expect(color.redComponent == 1)
        #expect(color.greenComponent == 1)
        #expect(color.blueComponent == 1)
        #expect(color.alphaComponent == 1)
    }
}
