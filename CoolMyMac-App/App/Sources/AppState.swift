// AppState.swift
// Observable shared state for the entire App.
// Refreshed periodically from the XPC daemon connection.

import Foundation
import SMCKit
import Observation

@Observable
@MainActor
final class AppState {

    // MARK: - Live Data

    var sensors: [SensorReading] = []
    var fans: [FanStatus] = []
    var activeProfile: FanProfile = .balanced

    // Derived: CPU and GPU temps for the popover tiles
    var cpuTemp: Double? { sensors.filter { $0.group == .cpuCore }.map(\.celsius).max() }
    var gpuTemp: Double? { sensors.filter { $0.group == .gpu }.map(\.celsius).max() }

    // Hottest sensor reading for the icon color gradient
    var hottestTemp: Double { sensors.map(\.celsius).max() ?? 0.0 }

    // MARK: - Daemon Status

    var daemonStatus: DaemonInstallStatus = .unknown
    var isRefreshing: Bool = false

    // MARK: - Settings (persisted in UserDefaults)

    @ObservationIgnored
    private let defaults = UserDefaults.standard

    var iconDisplayMode: IconDisplayMode {
        get { IconDisplayMode(rawValue: defaults.string(forKey: "iconDisplayMode") ?? "") ?? .iconOnly }
        set { defaults.set(newValue.rawValue, forKey: "iconDisplayMode") }
    }

    var dynamicIconEnabled: Bool {
        get { defaults.object(forKey: "dynamicIconEnabled") == nil ? true : defaults.bool(forKey: "dynamicIconEnabled") }
        set { defaults.set(newValue, forKey: "dynamicIconEnabled") }
    }

    // MARK: - Client

    var client = DaemonClient()
    private var refreshTimer: Timer?

    // MARK: - Lifecycle

    func startRefreshing() {
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stopRefreshing() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func refresh() {
        Task { @MainActor in
            isRefreshing = true
            async let s = client.readSensors()
            async let f = client.readFans()
            async let p = client.activeProfile()

            sensors = (try? await s) ?? sensors
            fans = (try? await f) ?? fans
            activeProfile = (try? await p) ?? activeProfile
            isRefreshing = false
        }
    }

    func setProfile(_ profile: FanProfile) {
        Task { @MainActor in
            try? await client.setActiveProfile(profile.id)
            activeProfile = profile
        }
    }
}

// MARK: - Supporting Types

enum IconDisplayMode: String, CaseIterable {
    case iconOnly = "icon"
    case iconAndTemp = "icon_temp"
    case iconAndRPM = "icon_rpm"

    var label: String {
        switch self {
        case .iconOnly:    return "Icon Only"
        case .iconAndTemp: return "Icon + CPU Temp"
        case .iconAndRPM:  return "Icon + Fan RPM"
        }
    }
}

enum DaemonInstallStatus {
    case installed
    case notInstalled
    case requiresApproval   // User denied, can re-request
    case unknown
}
