// Created by weixi on 2026/09/12.

import CatalogGenerator
import Foundation
import Testing

struct CatalogGeneratorTests {
    @Test func onlyChangesNamespaceAndVisibility() throws {
        let source = """
        private let resourceBundle = Foundation.Bundle.module
        nonisolated extension LocalizedStringResource {
            static var title: LocalizedStringResource { fatalError() }
            static func count(_ count: Int) -> LocalizedStringResource { fatalError() }
        }
        """
        let result = try CatalogGenerator.exposeSymbols(source)
        #expect(result.contains("public nonisolated enum I18n {"))
        #expect(result.contains("public static var title:"))
        #expect(result.contains("public static func count(_ count: Int)"))
        #expect(result.contains("private let resourceBundle = Foundation.Bundle.module"))
    }

    @Test(arguments: ["", "extension LocalizedStringResource {}", "public enum Strings {}"])
    func failsExplicitlyIfXcodeChangesOutput(source: String) {
        #expect(throws: CatalogError.self) { try CatalogGenerator.exposeSymbols(source) }
    }

    @Test func appleGeneratesNewTypedSymbolsWithoutChangingTheAdapter() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let catalog = directory.appendingPathComponent("Localizable.xcstrings")
        let data = Data(#"""
        {"sourceLanguage":"en","version":"1.0","strings":{
          "sampleTitle":{"extractionState":"manual","localizations":{"en":{"stringUnit":{"state":"translated","value":"A \"quote\""}}}},
          "sampleCount":{"extractionState":"manual","localizations":{"en":{"stringUnit":{"state":"translated","value":"%lld items"}}}},
          "sampleAmount":{"extractionState":"manual","localizations":{"en":{"stringUnit":{"state":"translated","value":"%1$(amount).2f"}}}}
        }}
        """#.utf8)
        try data.write(to: catalog)
        let result = try CatalogGenerator.generate(catalog: catalog)
        #expect(result.contains("public static var sampleTitle:"))
        #expect(result.contains("public static func sampleCount(_ arg1: Int)"))
        #expect(result.contains("public static func sampleAmount(amount: Float)"))
        #expect(!result.contains("@available(macOS 13,"))
    }

    @Test func repositoryCatalogIsCompleteAndGeneratedFileIsCurrent() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sources = root.appendingPathComponent("Packages/Localization/Sources/Localization")
        let catalog = sources.appendingPathComponent("Resources/Localizable.xcstrings")
        let generated = try CatalogGenerator.generate(catalog: catalog)
        #expect(generated == (try String(contentsOf: sources.appendingPathComponent("I18n.generated.swift"), encoding: .utf8)))
        let data = try Data(contentsOf: catalog)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let entries = try #require(object["strings"] as? [String: [String: Any]])
        let expected: Set<String> = ["en", "zh-Hans", "zh-Hant", "ja", "ko", "de", "fr", "es", "pt-BR"]
        for (key, entry) in entries {
            let locales = try #require(entry["localizations"] as? [String: Any])
            #expect(Set(locales.keys) == expected, "Missing language for \(key)")
            #expect(entry["extractionState"] as? String == "manual")
            #expect(generated.contains("static var \(key):") || generated.contains("static func \(key)("), "Missing symbol for \(key)")
        }
    }
}
