// CoolMyMacApp.swift
// @main entry point. Creates the MenuBarExtra and manages the preferences window.

import SwiftUI
import SMCKit

@main
struct CoolMyMacApp: App {

    @State private var state = AppState()
    @State private var preferencesOpen = false

    var body: some Scene {

        // MARK: - Menu Bar Extra
        MenuBarExtra {
            PopoverView(state: state, onOpenPreferences: { preferencesOpen = true })
                .frame(width: 320)
        } label: {
            MenuBarIconView(state: state)
        }
        .menuBarExtraStyle(.window)   // Renders the content as a floating panel

        // MARK: - Preferences Window
        Window("CoolMyMac Preferences", id: "preferences") {
            PreferencesView(state: state)
        }
        .defaultSize(width: 680, height: 520)
        .windowResizability(.contentMinSize)
    }
}
