//
//  CalculationHistory.swift
//  Mini Khmer Dictionary
//

import Foundation

/// One finished calculation.
struct CalculationRecord: Identifiable, Equatable {
    enum Source: Equatable { case simple, smart }
    
    let id = UUID()
    /// Exactly what was typed or keyed, so reusing it restores the input.
    let input: String
    /// The input as it reads best: canonical formula text, or the keypad's
    /// `1,500 − 15%` form.
    let expression: String
    let result: FormulaValue
    let source: Source
    
    var displayResult: String { FormulaFormatter.display(result) }
    var plainResult: String { FormulaFormatter.plain(result) }
}

/// Recent calculations for this session only — nothing is written to disk.
struct CalculationHistory: Equatable {
    static let capacity = 50
    
    /// Newest first.
    private(set) var records: [CalculationRecord] = []
    
    var isEmpty: Bool { records.isEmpty }
    
    /// Adds `record` unless it repeats the most recent one.
    mutating func add(_ record: CalculationRecord) {
        if let newest = records.first, newest.input == record.input, newest.result == record.result {
            return
        }
        records.insert(record, at: 0)
        if records.count > Self.capacity {
            records.removeLast(records.count - Self.capacity)
        }
    }
    
    mutating func remove(_ id: CalculationRecord.ID) {
        records.removeAll { $0.id == id }
    }
    
    mutating func clear() {
        records.removeAll()
    }
}
