# DesignSystem

A macOS UI foundation with no package, business, or app-configuration dependencies.

Color construction helpers for AppKit and SwiftUI:

```swift
NSColor(hex: 0x12ABEF)
Color(hex: 0x12ABEF, alpha: 0.5)
NSColor(hex: "#12ABEF") // Optional
Color(hex: "12abef", alpha: 0.5) // Optional
```

Integers use the low 24 bits as `0xRRGGBB`. Strings accept exactly six hex digits
with an optional `#`; invalid input returns nil. Both use sRGB and a separate
alpha argument, defaulting to 1.

System colors remain native. This package does not define a palette, product
tokens, or theme management.
