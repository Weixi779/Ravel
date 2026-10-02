//
//  LocalizedPresentationTests.swift
//  Ravel
//
//  Created by weixi on 2026/09/12.
//  Copyright © 2026 Ravel. All rights reserved.
//

import Foundation
import Localization
@testable import Ravel
import Testing

nonisolated struct LocalizedPresentationTests {
    @Test(arguments: ["", "No description", "中文 %@ 🚀\nsecond line"])
    func revisionCopyDoesNotTranslateRepositoryContent(description: String) {
        let row = Revision(
            commitID: "commit", changeID: "change", parentIDs: [], description: description,
            author: "author", email: "email", timestamp: .distantPast, bookmarks: [],
            isWorkingCopy: false, isImmutable: false, hasConflict: false, isDivergent: false, isEmpty: false,
        )
        if description.isEmpty {
            #expect(row.summary.isEmpty)
            #expect(row.displaySummary == String(localized: I18n.commonNoDescription))
        } else {
            #expect(row.displaySummary == description.components(separatedBy: "\n")[0])
        }
        #expect(row.description == description)
    }

    @Test
    func diffPreviewLimitIsLocalized() {
        #expect(FileDiff.Failure.tooLarge.localizedDescription == String(localized: I18n.errorsDiffTooLarge))
    }

    @Test
    func hostDeclaresTheLanguagesOfItsResourcePackage() throws {
        let languages = try #require(Bundle.main.object(forInfoDictionaryKey: "CFBundleLocalizations") as? [String])
        #expect(Set(languages) == ["en", "zh-Hans", "zh-Hant", "ja", "ko", "de", "fr", "es", "pt-BR"])
    }
}
