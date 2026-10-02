//
//  main.swift
//  Ravel
//
//  Created by weixi on 2026/09/12.
//  Copyright © 2026 Ravel. All rights reserved.
//

import CatalogGenerator
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
do {
    guard arguments.count == 2 || (arguments.count == 3 && arguments[2] == "--check") else {
        throw CatalogErrorForCLI.usage
    }
    let catalog = URL(fileURLWithPath: arguments[0])
    let output = URL(fileURLWithPath: arguments[1])
    let generated = try Data(CatalogGenerator.generate(catalog: catalog).utf8)
    let existing = try? Data(contentsOf: output)
    if arguments.count == 3 {
        guard existing == generated else { throw CatalogErrorForCLI.stale }
        print("Localization accessors are up to date.")
    } else if existing != generated {
        try generated.write(to: output, options: .atomic)
        print("Updated \(output.lastPathComponent).")
    }
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}

enum CatalogErrorForCLI: Error, CustomStringConvertible {
    case usage, stale
    var description: String {
        switch self {
        case .usage: "Usage: generate-localization <catalog> <output> [--check]"
        case .stale: "Generated localization accessors are stale. Run Tools/updateLocalization."
        }
    }
}
