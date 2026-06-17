// CoolMyMacApp.swift
// @main entry point. Creates the MenuBarExtra and manages the preferences window.

import SwiftUI
import SMCKit
import ServiceManagement

@main
struct CoolMyMacApp: App {

    @State private var state = AppState()

    init() {
        // Enforce single instance: prevent duplicate menu bar icons.
        // By terminating the OLD instances, clicking "Run" in Xcode seamlessly replaces the running app.
        if let bundleID = Bundle.main.bundleIdentifier {
            let currentPID = ProcessInfo.processInfo.processIdentifier
            let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            for app in apps where app.processIdentifier != currentPID {
                app.terminate()
            }
        }
        
        // Defaults: Open at login on first launch
        let hasLaunchedBefore = UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
        if !hasLaunchedBefore {
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            UserDefaults.standard.set(true, forKey: "openAtLogin")
            try? ServiceManagement.SMAppService.mainApp.register()
        }
    }

    var body: some Scene {

        // MARK: - Menu Bar Extra
        MenuBarExtra {
            PopoverView(state: state)
                .frame(width: 320)
                .onAppear { state.beginViewingAllSensors("popover") }
                .onDisappear { state.endViewingAllSensors("popover") }
        } label: {
            MenuBarIconView(state: state)
        }
        .menuBarExtraStyle(.window)   // Renders the content as a floating panel

        // MARK: - Preferences Window
        Window("CoolMyMac Preferences", id: "preferences") {
            PreferencesView(state: state)
        }
        .defaultSize(width: 500, height: 400)
        .windowResizability(.contentMinSize)
    }
}
