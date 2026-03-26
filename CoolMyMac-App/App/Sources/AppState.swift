// AppState.swift
// Observable shared state for the entire App.
// Refreshed periodically from the XPC daemon connection.

import Foundation
import SMCKit
import Observation
import os.log
import ServiceManagement

private let logger = Logger(subsystem: "com.coolmymac.app", category: "AppState")

@Observable
@MainActor
final class AppState {

    // MARK: - Live Data

    var sensors: [SensorReading] = []
    var fans: [FanStatus] = []
    var activeProfile: FanProfile = .balanced
    var customProfiles: [FanProfile] = []

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

    var iconDisplayMode: IconDisplayMode = {
        let saved = UserDefaults.standard.string(forKey: "iconDisplayMode") ?? ""
        return IconDisplayMode(rawValue: saved) ?? .iconAndTemp
    }() {
        didSet { defaults.set(iconDisplayMode.rawValue, forKey: "iconDisplayMode") }
    }

    var dynamicIconEnabled: Bool {
        get { defaults.object(forKey: "dynamicIconEnabled") == nil ? true : defaults.bool(forKey: "dynamicIconEnabled") }
        set { defaults.set(newValue, forKey: "dynamicIconEnabled") }
    }
    
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                    }
                }
            } catch {
                logger.error("Failed to toggle Launch at Login: \(error.localizedDescription)")
            }
        }
    }
    
    var updateInterval: Double = {
        let saved = UserDefaults.standard.double(forKey: "updateInterval")
        return saved == 0 ? 1.0 : saved
    }() {
        didSet {
            defaults.set(updateInterval, forKey: "updateInterval")
            Task { try? await client.setUpdateInterval(updateInterval) }
            stopRefreshing()
            startRefreshing()
        }
    }

    var activeSensors: Set<SensorGroup> = [.cpuCore, .gpu] {
        didSet {
            let array = Array(activeSensors)
            Task { try? await client.setActiveSensors(array) }
        }
    }

    var decimalResolution: Int = UserDefaults.standard.integer(forKey: "decimalResolution") {
        didSet { defaults.set(decimalResolution, forKey: "decimalResolution") }
    }

    // MARK: - Client

    var client = CoolMyMacClient()
    private var refreshTimer: Timer?

    // MARK: - Lifecycle

    init() {
        // Start refreshing immediately so data is preloaded
        startRefreshing()
    }

    func startRefreshing() {
        guard refreshTimer == nil else { return }  // prevent duplicate timers
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }
    func stopRefreshing() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func refresh() {
        Task { @MainActor in
            let baseStatus = DaemonManager.shared.currentStatus()
            
            isRefreshing = true
            let isReachable = await client.isDaemonReachable()
            
            if baseStatus == .installed && !isReachable {
                daemonStatus = .unreachable
            } else {
                daemonStatus = baseStatus
            }
            
            logger.info("Refreshing... daemonStatus=\(String(describing: self.daemonStatus)) reachable=\(isReachable)")
            
            if daemonStatus == .installed && isReachable {
                async let s = client.readSensors()
                async let f = client.readFans()
                async let p = client.activeProfile()
                async let a = client.getActiveSensors()
                async let c = client.getCustomProfiles()
                
                sensors = (try? await s) ?? sensors
                fans = (try? await f) ?? fans
                activeProfile = (try? await p) ?? activeProfile
                activeSensors = Set((try? await a) ?? [.cpuCore, .gpu])
                customProfiles = (try? await c) ?? customProfiles
            } else {
                let fallback = await Task.detached {
                    do {
                        let smc = try SMCController()
                        logger.info("SMCController init succeeded")
                        let s = (try? smc.readTemperatures()) ?? []
                        logger.info("readTemperatures returned \(s.count) sensors")
                        let f = (try? smc.readAllFans().map {
                            FanStatus(id: $0.id, name: $0.name, currentRPM: $0.currentRPM, minRPM: $0.minRPM, maxRPM: $0.maxRPM, isManaged: false)
                        }) ?? []
                        logger.info("readAllFans returned \(f.count) fans")
                        return (s, f)
                    } catch {
                        logger.error("SMC fallback failed: \(error.localizedDescription)")
                        return (Array<SensorReading>(), Array<FanStatus>())
                    }
                }.value
                
                if !fallback.0.isEmpty { sensors = fallback.0 }
                if !fallback.1.isEmpty { fans = fallback.1 }
                activeProfile = .quiet
            }
            logger.info("Refresh complete. sensors=\(self.sensors.count) fans=\(self.fans.count)")
            isRefreshing = false
        }
    }

    func setProfile(_ profile: FanProfile) {
        Task { @MainActor in
            if daemonStatus == .notInstalled {
                try? await DaemonManager.shared.installDaemon()
                return
            } else if daemonStatus == .requiresApproval {
                DaemonManager.shared.openSystemSettingsForApproval()
                return
            }
            
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
    case unreachable        // SMAppService says installed, but XPC pipe is dead
    case unknown
}
