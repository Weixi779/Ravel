//
//  ObservedDefaultDiagnosticTests.swift
//  Ravel
//
//  Created by weixi on 2026/09/16.
//  Copyright © 2026 Ravel. All rights reserved.
//

import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import Testing
@testable import UserDefaultsKitMacroPlugin

struct ObservedDefaultDiagnosticTests {
    @Test(arguments: [
        "@ObservedDefault(.key) let value: Int",
        "@ObservedDefault(.key) var value: Int = 1",
        "@ObservedDefault(.key) var value: Int { 1 }",
        "@ObservedDefault(.key) var value",
        "@ObservedDefault(.key) static var value: Int",
        "@ObservedDefault(.key) lazy var value: Int",
        "@ObservedDefault(.key) var first: Int, second: Int",
    ])
    func unsupportedDeclarationsProduceDiagnostics(_ source: String) throws {
        let declaration = DeclSyntax(stringLiteral: source)
        let property = try #require(declaration.as(VariableDeclSyntax.self))
        let attribute = try #require(property.attributes.first?.as(AttributeSyntax.self))
        #expect(throws: SwiftSyntaxMacros.MacroExpansionErrorMessage.self) {
            _ = try ObservedDefaultMacro.expansion(
                of: attribute,
                providingAccessorsOf: property,
                in: BasicMacroExpansionContext(),
            )
        }
    }

    @Test
    func observablePropertiesExplainWhyIgnoredIsRequired() throws {
        let declaration: DeclSyntax = "@ObservedDefault(.key) var value: Int"
        let property = try #require(declaration.as(VariableDeclSyntax.self))
        let attribute = try #require(property.attributes.first?.as(AttributeSyntax.self))
        let owner: DeclSyntax = "@Observable final class Model {}"
        let context = BasicMacroExpansionContext(lexicalContext: [Syntax(owner)])
        do {
            _ = try ObservedDefaultMacro.expansion(
                of: attribute,
                providingAccessorsOf: property,
                in: context,
            )
            Issue.record("An observable property must explain the missing @ObservationIgnored.")
        } catch let error as SwiftSyntaxMacros.MacroExpansionErrorMessage {
            #expect(error.message.contains("@ObservationIgnored"))
        }
    }
}
