//
//  PopoverRootView.swift
//  Mini Khmer Dictionary
//

import SwiftUI

/// Switches the popover between looking words up and checking text.
struct PopoverRootView: View {
    @ObservedObject var dictionary: DictionaryModel
    @ObservedObject var checker: SpellCheckModel

    var body: some View {
        VStack(spacing: 0) {
            Picker("Mode", selection: $dictionary.mode) {
                Text("Look Up").tag(PopoverMode.lookUp)
                Text("Check Spelling").tag(PopoverMode.check)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.vertical, 7)
            .help("⌘1 Look Up · ⌘2 Check Spelling")

            Divider()

            switch dictionary.mode {
            case .lookUp:
                DictionaryPopoverView(model: dictionary)
            case .check:
                SpellCheckView(model: checker, onLookUp: dictionary.lookUp)
            }
        }
        .frame(width: 620, height: 540)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
