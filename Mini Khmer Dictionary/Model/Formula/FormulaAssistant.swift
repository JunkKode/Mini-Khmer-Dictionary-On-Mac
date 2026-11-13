//
//  FormulaAssistant.swift
//  Mini Khmer Dictionary
//

import Foundation

/// Function names that could complete the word being typed.
struct FormulaCompletion: Equatable {
    /// UTF-16 range of the partial name to replace.
    let range: Range<Int>
    let prefix: String
    let names: [String]
}

/// The call the caret is inside, for the signature hint.
struct FormulaSignatureHint: Equatable {
    let functionName: String
    let argumentIndex: Int
}

/// Editor help that only needs the text and the caret: completions and
/// "which argument am I typing?".
enum FormulaAssistant {
    static let maximumSuggestions = 6

    static func completion(
        in source: String,
        caret: Int,
        registry: FormulaFunctionRegistry = .standard
    ) -> FormulaCompletion? {
        let tokens = FormulaLexer.tokenize(source)
        guard let index = tokens.firstIndex(where: { $0.range.upperBound == caret }),
              case .identifier(let name) = tokens[index].kind else { return nil }
        // Already a call: nothing to complete.
        if index + 1 < tokens.count, case .leftParen = tokens[index + 1].kind { return nil }

        let names = registry.functions(matchingPrefix: name).prefix(maximumSuggestions).map(\.name)
        guard !names.isEmpty else { return nil }
        return FormulaCompletion(range: tokens[index].range, prefix: name, names: Array(names))
    }

    static func signature(
        in source: String,
        caret: Int,
        registry: FormulaFunctionRegistry = .standard
    ) -> FormulaSignatureHint? {
        // Each open bracket before the caret: the function it belongs to (if
        // any) and how many separators have passed inside it.
        var frames: [(name: String?, arguments: Int)] = []
        var previous: FormulaToken?

        for token in FormulaLexer.tokenize(source) {
            guard token.range.lowerBound < caret else { break }
            switch token.kind {
            case .leftParen:
                var name: String?
                if case .identifier(let identifier)? = previous?.kind { name = identifier.uppercased() }
                frames.append((name, 0))
            case .rightParen:
                if token.range.upperBound <= caret, !frames.isEmpty { frames.removeLast() }
            case .separator:
                if !frames.isEmpty { frames[frames.count - 1].arguments += 1 }
            default:
                break
            }
            previous = token
        }

        guard let frame = frames.last(where: { $0.name != nil }),
              let name = frame.name,
              registry.function(named: name) != nil else { return nil }
        return FormulaSignatureHint(functionName: name, argumentIndex: frame.arguments)
    }
}
