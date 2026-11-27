//
//  RevisionPreviewCacheTests.swift
//  Ravel
//
//  Created by weixi on 2026/10/02.
//  Copyright © 2026 Ravel. All rights reserved.
//

import Foundation
@testable import Ravel
import Testing

@MainActor
struct RevisionPreviewCacheTests {
    @Test
    func previewCacheEvictsByCostAndSeparatesRepositoryAndOperation() throws {
        let diff = try RevisionPatchParser.parse("@@ -0,0 +1,1 @@\n+sample\n")
        let content = RevisionDiffPresentation(diff, fileName: "sample.swift")
        let cache = RevisionPreviewCache(byteLimit: content.estimatedBytes * 2)
        let revision = RevisionPreviewCache.Key(.init(repositoryURL: URL(fileURLWithPath: "/repo"), commitID: "a", operationID: "op"))
        let a = RevisionPreviewCache.FileKey(revision: revision, path: "a")
        let b = RevisionPreviewCache.FileKey(revision: revision, path: "b")
        let c = RevisionPreviewCache.FileKey(revision: revision, path: "c")
        cache.store(content, for: a)
        cache.store(content, for: b)
        #expect(cache.content(a) != nil)
        cache.store(content, for: c)
        #expect(cache.content(b) == nil)
        #expect(cache.content(a) != nil && cache.content(c) != nil)
        let otherOperation = RevisionPreviewCache.Key(.init(repositoryURL: URL(fileURLWithPath: "/repo"), commitID: "a", operationID: "other"))
        #expect(cache.content(.init(revision: otherOperation, path: "a")) == nil)
        cache.clear()
        #expect(cache.content(a) == nil)
    }
}
