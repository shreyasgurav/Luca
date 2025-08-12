//
//  cheatingaiApp.swift
//  cheatingai
//
//  Created by Shreyas Gurav on 09/08/25.
//

import SwiftUI
import AppKit

@main
struct cheatingaiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings { EmptyView() }
    }
}
