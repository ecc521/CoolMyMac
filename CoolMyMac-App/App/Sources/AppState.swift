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
    var cpuTemp: Double? { sensors.filter { $0.group == .cpuCore }.map(\.value).max() }
    var gpuTemp: Double? { sensors.filter { $0.group == .gpu }.map(\.value).max() }

    // Hottest sensor reading for the icon color gradient
    var hottestTemp: Double {
        let coreTemps = sensors.filter { $0.group == .cpuCore || $0.group == .gpu }.map(\.value)
        return coreTemps.max() ?? (sensors.map(\.value).max() ?? 0.0)
    }

    // MARK: - Daemon Status

    var daemonStatus: DaemonInstallStatus = .unknown
    var isRefreshing: Bool = false
    var lastSensorsUpdate: Date? = nil

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
                logger.error("Failed to set login item: \(error.localizedDescription)")
            }
        }
    }

    var allowUnprivilegedCLI: Bool = false

    func setAllowUnprivilegedCLI(_ allow: Bool) {
        allowUnprivilegedCLI = allow
        Task { try? await client.setAllowUnprivilegedCLI(allow) }
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
            let excludedArray = Array(excludedSensors)
            Task { try? await client.setActiveSensors(array, excludedSensors: excludedArray) }
        }
    }

    var excludedSensors: Set<String> = [] {
        didSet {
            let array = Array(activeSensors)
            let excludedArray = Array(excludedSensors)
            Task { try? await client.setActiveSensors(array, excludedSensors: excludedArray) }
        }
    }

    var decimalResolution: Int = UserDefaults.standard.integer(forKey: "decimalResolution") {
        didSet { defaults.set(decimalResolution, forKey: "decimalResolution") }
    }

    // MARK: - Client

    var client = CoolMyMacClient()
    private var refreshTask: Task<Void, Never>?
    var updateChecker = UpdateChecker()

    // MARK: - Lifecycle

    init() {
        // Start refreshing immediately so data is preloaded
        startRefreshing()
        
        Task {
            await updateChecker.checkForUpdates()
        }
    }

    func startRefreshing() {
        guard refreshTask == nil else { return }  // prevent duplicate loops
        refresh()
        
        refreshTask = Task { @MainActor [weak self] in
            let activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
                reason: "CoolMyMac Menu Bar Updates"
            )
            defer { ProcessInfo.processInfo.endActivity(activity) }
            
            while !Task.isCancelled {
                guard let self = self else { break }
                try? await Task.sleep(nanoseconds: UInt64(self.updateInterval * 1_000_000_000))
                if !Task.isCancelled {
                    self.refresh()
                }
            }
        }
    }
    
    func stopRefreshing() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    var isViewingAllSensors: Bool = false {
        didSet {
            if isViewingAllSensors && !oldValue {
                refresh()
            }
        }
    }
    private var hasCheckedDaemonVersion = false

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
                if !hasCheckedDaemonVersion {
                    hasCheckedDaemonVersion = true
                    if let dVersion = try? await client.getDaemonVersion(),
                       let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                       dVersion != appVersion {
                        logger.info("Daemon version mismatch (\(dVersion) vs app \(appVersion)). Auto-repairing daemon...")
                        try? await DaemonManager.shared.repairDaemon()
                        isRefreshing = false
                        return
                    }
                }
                
                async let s = isViewingAllSensors ? client.readAllSensors() : client.readSensors()
                async let f = client.readFans()
                async let p = client.activeProfile()
                async let c = client.getCustomProfiles()
                async let u = client.getAllowUnprivilegedCLI()
                
                sensors = (try? await s) ?? sensors
                fans = (try? await f) ?? fans
                activeProfile = (try? await p) ?? activeProfile
                let globalSensors = try? await client.getActiveSensors()
                activeSensors = Set(globalSensors?.groups ?? [.cpuCore, .gpu])
                excludedSensors = Set(globalSensors?.excludedSensors ?? [])
                customProfiles = (try? await c) ?? customProfiles
                if let allow = try? await u { allowUnprivilegedCLI = allow }
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
                activeProfile = .system
            }
            logger.info("Refresh complete. sensors=\(self.sensors.count) fans=\(self.fans.count)")
            lastSensorsUpdate = Date()
            isRefreshing = false
        }
    }

    func setProfile(_ profile: FanProfile) {
        Task {
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

// MARK: - Auto Updater

struct GitHubRelease: Codable {
    let tagName: String
    let htmlUrl: String
    
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlUrl = "html_url"
    }
}

@MainActor
@Observable
final class UpdateChecker {
    var updateAvailable: Bool = false
    var latestVersion: String = ""
    var releaseUrl: URL? = nil
    
    private let logger = Logger(subsystem: "com.coolmymac.app", category: "UpdateChecker")
    private let repoAPIUrl = URL(string: "https://api.github.com/repos/ecc521/CoolMyMac/releases/latest")!
    
    func checkForUpdates() async {
        do {
            var request = URLRequest(url: repoAPIUrl)
            request.timeoutInterval = 10.0
            request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
                logger.warning("Failed to check for updates: Invalid HTTP response")
                return
            }
            
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            
            // "v1.2.0" -> "1.2.0"
            let latestVersionString = release.tagName.replacingOccurrences(of: "v", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            
            let currentVersionString = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
            
            if isVersion(latestVersionString, strictlyGreaterThan: currentVersionString) {
                self.updateAvailable = true
                self.latestVersion = latestVersionString
                self.releaseUrl = URL(string: release.htmlUrl)
                logger.info("Update available! Current: \(currentVersionString), Latest: \(latestVersionString)")
            } else {
                logger.info("App is up to date. Current: \(currentVersionString), Latest: \(latestVersionString)")
            }
        } catch {
            logger.error("Error checking for updates: \(error.localizedDescription)")
        }
    }
    
    private func isVersion(_ v1: String, strictlyGreaterThan v2: String) -> Bool {
        let components1 = v1.split(separator: ".").compactMap { Int($0) }
        let components2 = v2.split(separator: ".").compactMap { Int($0) }
        
        let count = max(components1.count, components2.count)
        
        for i in 0..<count {
            let c1 = i < components1.count ? components1[i] : 0
            let c2 = i < components2.count ? components2[i] : 0
            
            if c1 > c2 { return true }
            if c1 < c2 { return false }
        }
        
        return false
    }
}
