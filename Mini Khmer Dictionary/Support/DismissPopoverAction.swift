//
//  DismissPopoverAction.swift
//  Mini Khmer Dictionary
//

import SwiftUI

/// Lets any view close the menu bar popover without knowing who presented it.
struct DismissPopoverAction {
    private let handler: @MainActor () -> Void

    init(handler: @escaping @MainActor () -> Void = {}) {
        self.handler = handler
    }

    @MainActor
    func callAsFunction() {
        handler()
    }
}

extension EnvironmentValues {
    @Entry var dismissPopover = DismissPopoverAction()
}
