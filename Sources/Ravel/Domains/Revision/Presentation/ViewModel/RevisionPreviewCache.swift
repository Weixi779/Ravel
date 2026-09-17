// Created by weixi on 2026/09/18.

import Foundation

/// Window-scoped previews. Clearing the repository releases every retained value.
@MainActor
final class RevisionPreviewCache {
    struct Key: Hashable {
        let repository: URL
        let commit: String
        let operation: String

        init(_ request: RevisionDiffRequest) {
            repository = request.repositoryURL
            commit = request.commitID
            operation = request.operationID
        }
    }

    struct FileKey: Hashable {
        let revision: Key
        let path: String
    }

    private var revisions: [Key: RevisionDiff] = [:]
    private var statistics: [Key: RevisionDiffStatistics] = [:]
    private var selections: [Key: String] = [:]
    private var revisionOrder: [Key] = []
    private var contents: [FileKey: RevisionDiffPresentation] = [:]
    private var contentOrder: [FileKey] = []
    private var contentBytes = 0
    private let byteLimit: Int

    init(byteLimit: Int = 64 * 1024 * 1024) {
        self.byteLimit = byteLimit
    }

    func revision(_ key: Key) -> RevisionDiff? {
        revisions[key]
    }

    func statistics(_ key: Key) -> RevisionDiffStatistics? {
        statistics[key]
    }

    func selection(_ key: Key) -> String? {
        selections[key]
    }

    func select(_ path: String?, in key: Key) {
        selections[key] = path
    }

    func store(_ revision: RevisionDiff, for key: Key) {
        revisions[key] = revision
        revisionOrder.removeAll { $0 == key }
        revisionOrder.append(key)
        while revisionOrder.count > 24 {
            let evicted = revisionOrder.removeFirst()
            revisions[evicted] = nil
            statistics[evicted] = nil
            selections[evicted] = nil
            for file in contentOrder.filter({ $0.revision == evicted }) {
                remove(file)
            }
        }
    }

    func store(_ statistics: RevisionDiffStatistics, for key: Key) {
        self.statistics[key] = statistics
    }

    func content(_ key: FileKey) -> RevisionDiffPresentation? {
        guard let result = contents[key] else { return nil }
        contentOrder.removeAll { $0 == key }
        contentOrder.append(key)
        return result
    }

    func store(_ content: RevisionDiffPresentation, for key: FileKey) {
        remove(key)
        guard content.estimatedBytes <= byteLimit else { return }
        contents[key] = content
        contentOrder.append(key)
        contentBytes += content.estimatedBytes
        while contentBytes > byteLimit, let oldest = contentOrder.first {
            remove(oldest)
        }
    }

    func clear() {
        revisions.removeAll()
        statistics.removeAll()
        selections.removeAll()
        revisionOrder.removeAll()
        contents.removeAll()
        contentOrder.removeAll()
        contentBytes = 0
    }

    private func remove(_ key: FileKey) {
        if let value = contents.removeValue(forKey: key) { contentBytes -= value.estimatedBytes }
        contentOrder.removeAll { $0 == key }
    }
}
