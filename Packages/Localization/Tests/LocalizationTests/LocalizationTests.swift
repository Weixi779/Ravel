// Created by weixi on 2026/09/12.

import Foundation
import Localization
import Testing

struct LocalizationTests {
    private func resolve(_ resource: LocalizedStringResource, language: String) -> String {
        var resource = resource
        resource.locale = Locale(identifier: language)
        return String(localized: resource)
    }

    @Test(arguments: [
        ("en", "Open Repository…"), ("zh-Hans", "打开仓库…"), ("zh-Hant", "開啟儲存庫…"),
        ("ja", "リポジトリを開く…"), ("ko", "저장소 열기…"), ("de", "Repository öffnen…"),
        ("fr", "Ouvrir un dépôt…"), ("es", "Abrir repositorio…"), ("pt-BR", "Abrir repositório…"),
    ])
    func packageResourceUsesRequestedLanguage(language: String, expected: String) {
        #expect(resolve(I18n.repositoryOpen, language: language) == expected)
    }

    @Test(arguments: [
        ("en", 0, "0 changes"), ("en", 1, "1 change"), ("en", 2, "2 changes"),
        ("fr", 0, "0 changement"), ("fr", 1, "1 changement"), ("fr", 2, "2 changements"),
        ("de", 1, "1 Änderung"), ("de", 2, "2 Änderungen"),
        ("pt-BR", 0, "0 alteração"), ("pt-BR", 2, "2 alterações"),
        ("zh-Hans", 2, "2 个变更"), ("ko", 2, "변경 2개"),
    ])
    func selectsPluralByLanguage(language: String, count: Int, expected: String) {
        #expect(resolve(I18n.historyChangeCount(count), language: language) == expected)
    }

    @Test
    func preservesArgumentsAsLiteralContent() {
        let path = "folder/中文 \"100%@\"\\file\n.swift"
        #expect(resolve(I18n.historyRevisionIdentity(path, "commit🚀"), language: "en") == "Change \(path)\nCommit commit🚀")
        #expect(resolve(I18n.historyRevisionIdentity("change%lld", "commit🚀"), language: "en") == "Change change%lld\nCommit commit🚀")
    }

    @Test
    func unsupportedLanguageFallsBackToEnglish() {
        #expect(resolve(I18n.repositoryOpen, language: "zz") == "Open Repository…")
    }
}
