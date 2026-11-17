//
//  GridKeyboard.swift
//  Mini Khmer Dictionary
//

import AppKit

extension GridModel {
    /// Keys while the Grid is showing, from `AppDelegate`'s local monitor via
    /// `CalculatorModel`. Returns `true` when the key was consumed.
    ///
    /// While a cell is being edited the formula bar is a real text view and
    /// gets every key; Return, Tab and ↑/↓ come back through `handle(_:)`, and
    /// Escape through `handleEscape()`. A sheet being renamed gets its keys
    /// too.
    func handleKeyDown(_ event: NSEvent) -> Bool {
        guard !isEditing, renamingSheet == nil else { return false }
        
        let flags = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function, .capsLock])
        let key = event.charactersIgnoringModifiers?.lowercased()
        
        // Undo and redo answer to ⌘ or Ctrl, as on other platforms.
        let commandLike = flags == .command || flags == .control
        let shiftedCommandLike = flags == [.command, .shift] || flags == [.control, .shift]
        switch key {
            case "z" where commandLike: undo(); return true
            case "z" where shiftedCommandLike, "y" where commandLike: redo(); return true
            default: break
        }
        
        if flags == .command {
            switch key {
                case "c": copySelection()
                case "x": cutSelection()
                case "v": paste()
                default: return false
            }
            return true
        }
        // ⇧⌘V and ⌥⇧⌘V paste values only, like "Paste and Match Style".
        if key == "v", flags == [.command, .shift] || flags == [.command, .shift, .option] {
            paste(.values)
            return true
        }
        
        guard flags.isSubset(of: .shift) else { return false }
        let shift = flags.contains(.shift)
        
        switch event.keyCode {
            case 123: shift ? extendSelection(columns: -1) : move(columns: -1)   // ←
            case 124: shift ? extendSelection(columns: 1) : move(columns: 1)     // →
            case 125: shift ? extendSelection(rows: 1) : move(rows: 1)           // ↓
            case 126: shift ? extendSelection(rows: -1) : move(rows: -1)         // ↑
            case 48: move(columns: shift ? -1 : 1)                               // tab
            case 36, 76: move(rows: shift ? -1 : 1)                              // return, enter
            case 120: beginEditing()                                             // F2
            case 51, 117: clearSelection()                                       // delete, forward delete
            case 115: select(CellAddress(column: 0, row: activeCell.row))        // home
            default:
                // Any printable character starts an edit with that character.
                guard let characters = event.characters, !characters.isEmpty,
                      characters.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F && !(0xF700...0xF8FF).contains($0.value) })
                        else { return false }
                beginEditing(with: characters)
        }
        return true
    }
}
