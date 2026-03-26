// CoolMyMacApp.swift
// @main entry point. Creates the MenuBarExtra and manages the preferences window.

import SwiftUI
import SMCKit

@main
struct CoolMyMacApp: App {

    @State private var state = AppState()

    init() {
        // Enforce single instance: prevent duplicate menu bar icons when launching from Xcode repeatedly
        if let bundleID = Bundle.main.bundleIdentifier {
            let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            if apps.count > 1 {
                if let oldApp = apps.first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
                    oldApp.activate(options: .activateIgnoringOtherApps)
                }
                exit(0)
            }
        }
    }

    var body: some Scene {

        // MARK: - Menu Bar Extra
        MenuBarExtra {
            PopoverView(state: state)
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
