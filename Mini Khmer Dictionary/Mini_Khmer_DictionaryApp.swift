//
//  Mini_Khmer_DictionaryApp.swift
//  Mini Khmer Dictionary
//
//  Created by KimKuong on 9/9/26.
//

import SwiftUI

@main
struct Mini_Khmer_DictionaryApp: App {
    /// All of the interface lives in the status bar popover the delegate owns;
    /// the app itself deliberately has no windows.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
