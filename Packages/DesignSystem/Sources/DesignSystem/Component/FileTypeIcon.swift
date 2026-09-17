// Created by weixi on 2026/09/18.

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Type-based lookup also works for historical and deleted files that are absent on disk.
public struct FileTypeIcon: View {
    private let fileName: String
    private let size: CGFloat

    public init(fileName: String, size: CGFloat = 16) {
        self.fileName = fileName
        self.size = size
    }

    public var body: some View {
        Image(nsImage: FileTypeIcons.image(for: fileName))
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

@MainActor
private enum FileTypeIcons {
    static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 256
        return cache
    }()

    static func image(for fileName: String) -> NSImage {
        let suffix = (fileName as NSString).pathExtension.lowercased()
        let type = UTType(filenameExtension: suffix) ?? .data
        let key = type.identifier as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let image = NSWorkspace.shared.icon(for: type)
        cache.setObject(image, forKey: key)
        return image
    }
}
