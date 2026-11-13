//
//  CalculatorKeyboard.swift
//  Mini Khmer Dictionary
//

import AppKit

extension SimpleCalculator.Key {
    /// The keypad key a typed character stands for.
    init?(typed character: Character) {
        switch character {
        case "0"..."9": self = .digit(Int(String(character))!)
        case "០"..."៩": self = .digit(Int(character.unicodeScalars.first!.value - 0x17E0))
        case ".", ",": self = .decimal
        case "+": self = .op(.add)
        case "-", "−": self = .op(.subtract)
        case "*", "x", "X", "×": self = .op(.multiply)
        case "/", "÷": self = .op(.divide)
        case "^": self = .op(.power)
        case "%": self = .percent
        case "(": self = .openParen
        case ")": self = .closeParen
        case "=": self = .equals
        case "c", "C": self = .clear
        case "n", "N", "±": self = .toggleSign
        default: return nil
        }
    }
}

extension CalculatorModel {
    /// Called from `AppDelegate`'s local key monitor while the Calculator tab
    /// is showing. Returns `true` when the key was consumed.
    ///
    /// The formula editor is a real text view, so in Smart mode almost every
    /// key is left to it; the keypad has nothing focusable, so in Simple mode
    /// the keys are translated here.
    func handleKeyDown(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function, .capsLock])

        if flags == .command {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "c": return copyResultForShortcut()
            case "v" where mode == .simple: return pasteIntoSimple()
            default: return false
            }
        }

        guard mode == .simple, flags.isSubset(of: .shift) else { return false }

        switch event.keyCode {
        case 36, 76:  // return, keypad enter
            press(.equals, fromKeyboard: true)
            return true
        case 51, 117:  // delete, forward delete
            press(.backspace, fromKeyboard: true)
            return true
        case 126:  // up arrow
            return browseHistory(older: true)
        case 125:  // down arrow
            return browseHistory(older: false)
        default:
            break
        }

        guard let characters = event.characters, characters.count == 1,
              let key = SimpleCalculator.Key(typed: characters.first!) else { return false }
        press(key, fromKeyboard: true)
        return true
    }
}
