//
//  DictionaryEntry.swift
//  Mini Khmer Dictionary
//

import Foundation

/// One headword of the dictionary, in the shape the list needs to draw a row.
///
/// The senses are deliberately *not* part of this type: a search can return
/// hundreds of rows and decoding every definition up front is wasted work.
/// They are fetched separately for the entry the user selects.
struct DictionaryEntry: Identifiable, Hashable, Sendable {
    let id: Int
    let word: String
    let pronunciation: String
    let partOfSpeech: String
    let gloss: String
    /// Approximate Latin transcription, e.g. `tamley` for តម្លៃ. Generated at
    /// build time and used both for romanized search and as a reading hint.
    let roman: String
    /// `true` for compound words (`t_level` 2) that hang off a simpler headword.
    let isCompound: Bool
}

/// A numbered meaning of a headword.
struct DictionarySense: Hashable, Sendable, Decodable {
    let number: String
    let partOfSpeech: String
    let definition: String
    let example: String
    let note: String

    private enum CodingKeys: String, CodingKey {
        case number = "n"
        case partOfSpeech = "p"
        case definition = "d"
        case example = "e"
        case note
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        number = try container.decodeIfPresent(String.self, forKey: .number) ?? ""
        partOfSpeech = try container.decodeIfPresent(String.self, forKey: .partOfSpeech) ?? ""
        definition = try container.decodeIfPresent(String.self, forKey: .definition) ?? ""
        example = try container.decodeIfPresent(String.self, forKey: .example) ?? ""
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
    }
}

extension DictionaryEntry {
    /// Multi-line plain text used when the whole entry is copied.
    func formattedForCopying(senses: [DictionarySense]) -> String {
        var lines: [String] = []

        var heading = word
        if !pronunciation.isEmpty { heading += "  \(pronunciation)" }
        if !partOfSpeech.isEmpty { heading += "  \(partOfSpeech)" }
        lines.append(heading)

        for sense in senses {
            var line = sense.definition
            if !sense.number.isEmpty { line = "\(sense.number) \(line)" }
            if !line.isEmpty { lines.append(line) }
            if !sense.example.isEmpty { lines.append("    \(sense.example)") }
            if !sense.note.isEmpty { lines.append("    \(sense.note)") }
        }

        if lines.count == 1, !gloss.isEmpty { lines.append(gloss) }
        return lines.joined(separator: "\n")
    }
}
