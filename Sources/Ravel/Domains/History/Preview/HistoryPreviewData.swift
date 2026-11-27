//
//  HistoryPreviewData.swift
//  Ravel
//
//  Created by weixi on 2026/11/27.
//  Copyright © 2026 Ravel. All rights reserved.
//

#if DEBUG
    import Foundation

    enum HistoryPreviewData {
        static let source = Revision(
            commitID: "d2edccd1",
            changeID: "kwvroosn",
            parentIDs: [],
            description: "Preserve selection\n\nLocate the rewritten commit.\nKeep the original selection on cancel.",
            author: "weixi",
            email: "weixi@example.com",
            timestamp: .now,
            bookmarks: ["history"],
            isWorkingCopy: false,
            isImmutable: false,
            hasConflict: false,
            isDivergent: false,
            isEmpty: false,
        )
    }
#endif
