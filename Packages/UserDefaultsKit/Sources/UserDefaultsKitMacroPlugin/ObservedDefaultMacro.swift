// Created by weixi on 2026/09/16.

import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

struct ObservedDefaultMacro: AccessorMacro {
    static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext,
    ) throws -> [AccessorDeclSyntax] {
        guard let property = declaration.as(VariableDeclSyntax.self),
              property.bindingSpecifier.tokenKind == .keyword(.var),
              property.bindings.count == 1,
              let binding = property.bindings.first,
              binding.pattern.is(IdentifierPatternSyntax.self)
        else {
            throw MacroExpansionErrorMessage("@ObservedDefault requires a single var property.")
        }
        guard !property.modifiers.contains(where: {
            [.keyword(.static), .keyword(.class), .keyword(.lazy)].contains($0.name.tokenKind)
        }) else {
            throw MacroExpansionErrorMessage("@ObservedDefault requires a non-lazy instance property.")
        }
        guard binding.initializer == nil, binding.accessorBlock == nil else {
            throw MacroExpansionErrorMessage(
                "@ObservedDefault generates get/set; declare the default value in UserDefaultsKey.",
            )
        }
        guard binding.typeAnnotation != nil else {
            throw MacroExpansionErrorMessage("@ObservedDefault requires an explicit property type.")
        }
        if context.lexicalContext.contains(where: { syntax in
            guard let type = syntax.as(ClassDeclSyntax.self) else { return false }
            return hasAttribute("Observable", in: type.attributes)
        }), !hasAttribute("ObservationIgnored", in: property.attributes) {
            throw MacroExpansionErrorMessage(
                "Add @ObservationIgnored so @ObservedDefault owns this property's accessors.",
            )
        }
        guard case let .argumentList(arguments) = node.arguments,
              let key = arguments.first?.expression
        else {
            throw MacroExpansionErrorMessage("@ObservedDefault requires a UserDefaultsKey.")
        }
        let store: ExprSyntax = if let keyPath = arguments.first(where: { $0.label?.text == "store" })?.expression {
            "self[keyPath: \(keyPath)]"
        } else {
            "UserDefaultsKit.UserDefaultsStore.standard"
        }
        return [
            """
            get {
                return (\(store)).observedValue(for: \(key))
            }
            """,
            """
            set {
                let accessor = UserDefaultsKit.UserDefault(\(key), store: \(store))
                accessor.wrappedValue = newValue
            }
            """,
        ]
    }

    private static func hasAttribute(_ name: String, in attributes: AttributeListSyntax) -> Bool {
        attributes.contains { element in
            guard let attribute = element.as(AttributeSyntax.self) else { return false }
            return attribute.attributeName.trimmedDescription.split(separator: ".").last.map(String.init) == name
        }
    }
}

@main
struct UserDefaultsKitPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [ObservedDefaultMacro.self]
}
