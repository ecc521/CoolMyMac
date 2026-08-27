// AppState.swift
// Observable shared state for the entire App.
// Refreshed periodically from the XPC daemon connection.

import Foundation
import AppKit
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
    var daemonVersion: String? = nil
    var isRefreshing: Bool = false
    var lastSensorsUpdate: Date? = nil

    // MARK: - Settings (persisted in UserDefaults)

    @ObservationIgnored
    private let defaults = UserDefaults.standard

    @ObservationIgnored
    private var appActivationObserver: NSObjectProtocol?

    var iconDisplayMode: IconDisplayMode = {
        let saved = UserDefaults.standard.string(forKey: "iconDisplayMode") ?? ""
        return IconDisplayMode(rawValue: saved) ?? .iconAndTemp
    }() {
        didSet { defaults.set(iconDisplayMode.rawValue, forKey: "iconDisplayMode") }
    }

    var menuBarItemLayout: MenuBarItemLayout = {
        let saved = UserDefaults.standard.string(forKey: "menuBarItemLayout") ?? ""
        return MenuBarItemLayout(rawValue: saved) ?? .horizontal
    }() {
        didSet { defaults.set(menuBarItemLayout.rawValue, forKey: "menuBarItemLayout") }
    }

    // Stored (not computed) for the same reason as launchAtLogin below — a computed
    // get/set backed directly by UserDefaults is invisible to Observation, so neither
    // the toggle nor the icon's live color would update when this changed.
    var dynamicIconEnabled: Bool = {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: "dynamicIconEnabled") == nil ? true : defaults.bool(forKey: "dynamicIconEnabled")
    }() {
        didSet { defaults.set(dynamicIconEnabled, forKey: "dynamicIconEnabled") }
    }
    
    // Stored (not computed) so mutating it actually notifies Observation and re-renders
    // the toggle. A computed get/set backed directly by SMAppService.mainApp.status never
    // fires a change notification — the checkbox would visually stick at whatever it showed
    // on the last unrelated re-render.
    var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled {
        didSet {
            guard oldValue != launchAtLogin else { return }
            do {
                if launchAtLogin {
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
                // Revert to the actual system state since the change failed.
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    // Re-reads SMAppService's status in case it changed outside this toggle (e.g. the
    // user disabled it from System Settings > Login Items directly).
    func refreshLaunchAtLoginStatus() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    var allowUnprivilegedCLI: Bool = false
    var heavyFailsafeSpeed: Double = 0.50
    var criticalFailsafeSpeed: Double = 1.00

    func setAllowUnprivilegedCLI(_ allow: Bool) {
        allowUnprivilegedCLI = allow
        Task { try? await client.setAllowUnprivilegedCLI(allow) }
    }

    func setThermalFailsafeSpeeds(heavy: Double, critical: Double) {
        heavyFailsafeSpeed = heavy
        criticalFailsafeSpeed = critical
        Task { try? await client.setThermalFailsafeSpeeds(heavy: heavy, critical: critical) }
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
    private var currentRefreshTask: Task<Void, Never>?
    var updateChecker = UpdateChecker()

    // MARK: - Lifecycle

    init() {
        syncStaticSettings()
        // Start refreshing immediately so data is preloaded
        startRefreshing()

        Task {
            await updateChecker.checkForUpdates()
        }

        // When the user returns from System Settings (after granting daemon approval),
        // the app becomes active again. Force a status re-check so the UI doesn't stay
        // stuck on "requires approval" or "unknown" after the grant is made.
        appActivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.refreshLaunchAtLoginStatus()
                guard self.daemonStatus != .installed else { return }
                self.refresh()
            }
        }
    }

    func syncStaticSettings() {
        Task {
            async let p = client.activeProfile()
            async let c = client.getCustomProfiles()
            async let u = client.getAllowUnprivilegedCLI()
            async let tf = client.getThermalFailsafeSpeeds()
            async let globalSensors = client.getActiveSensors()
            
            if let fetchedProfile = try? await p {
                self.activeProfile = fetchedProfile
            }
            if let fetchedCustom = try? await c {
                let order = UserDefaults.standard.stringArray(forKey: "ProfileOrder") ?? ["balanced", "performance", "max"]
                self.customProfiles = fetchedCustom.sorted { a, b in
                    let aIdx = order.firstIndex(of: a.id) ?? Int.max
                    let bIdx = order.firstIndex(of: b.id) ?? Int.max
                    if aIdx == bIdx { return a.id < b.id }
                    return aIdx < bIdx
                }
            }
            if let fetchedAllowCLI = try? await u {
                self.allowUnprivilegedCLI = fetchedAllowCLI
            }
            if let fetchedThermalFailsafe = try? await tf {
                self.heavyFailsafeSpeed = fetchedThermalFailsafe.heavy
                self.criticalFailsafeSpeed = fetchedThermalFailsafe.critical
            }
            if let globalSensors = try? await globalSensors {
                self.activeSensors = Set(globalSensors.groups)
                self.excludedSensors = Set(globalSensors.excludedSensors)
            }
        }
    }

    private var refreshSubscribers = 0
    
    func startRefreshing() {
        refreshSubscribers += 1
        guard refreshTask == nil else { return }  // prevent duplicate loops
        refresh()
        
        refreshTask = Task(priority: .utility) { @MainActor [weak self] in
            let activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiatedAllowingIdleSystemSleep],
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
        refreshSubscribers -= 1
        if refreshSubscribers <= 0 {
            refreshSubscribers = 0
            refreshTask?.cancel()
            refreshTask = nil
            currentRefreshTask?.cancel()
            currentRefreshTask = nil
            isRefreshing = false
            client.disconnect() // Disconnect from XPC so daemon can suspend
        }
    }

    // Tracks which UI surfaces currently need the full sensor sweep (popover,
    // Sensors preferences tab). Ref-counted by token rather than a single Bool so
    // that closing one surface can't clobber the flag for another that's still open.
    // A Set (vs. a counter) is idempotent against SwiftUI's occasional duplicate or
    // out-of-order onAppear/onDisappear callbacks.
    private var fullSensorViewers: Set<String> = []

    var isViewingAllSensors: Bool { !fullSensorViewers.isEmpty }

    func beginViewingAllSensors(_ token: String) {
        let wasEmpty = fullSensorViewers.isEmpty
        fullSensorViewers.insert(token)
        if wasEmpty {
            syncStaticSettings()
            refresh()  // immediate full read on 0 -> 1 transition
        }
    }

    func endViewingAllSensors(_ token: String) {
        fullSensorViewers.remove(token)
        if fullSensorViewers.isEmpty {
            // Groups outside the driving set (vrm, wireless, power, etc.) won't be
            // refreshed again until a full-view surface reopens. Reset the flag so the
            // next reopen shows a loading state instead of quietly re-presenting whatever
            // values are still sitting in `sensors` from before as if they were current.
            hasFullSensorSweep = false
        }
    }

    // True once a full sweep (readAllSensors) has completed since the last time every
    // full-view surface (popover, Sensors tab) was closed. Views use this to distinguish
    // "no data for this group yet" from "this group genuinely doesn't exist on this Mac."
    var hasFullSensorSweep: Bool = false

    private var hasCheckedDaemonVersion = false

    func refresh() {
        currentRefreshTask?.cancel()
        isRefreshing = true
        
        currentRefreshTask = Task { @MainActor in
            defer {
                if !Task.isCancelled {
                    isRefreshing = false
                }
            }
            
            let baseStatus = DaemonManager.shared.currentStatus()
            let isReachable = await client.isDaemonReachable()
            
            if Task.isCancelled { return }
            
            if isReachable {
                // XPC reachability is the ground truth. If the daemon responds,
                // it's running — trust this over SMAppService.status, which can
                // lag or return stale values on macOS 26+ after approval grants.
                daemonStatus = .installed
            } else if baseStatus == .installed {
                daemonStatus = .unreachable
                hasCheckedDaemonVersion = false
            } else {
                daemonStatus = baseStatus
            }
            
            logger.info("Refreshing... daemonStatus=\(String(describing: self.daemonStatus)) reachable=\(isReachable)")
            
            if daemonStatus == .installed && isReachable {
                if !hasCheckedDaemonVersion {
                    hasCheckedDaemonVersion = true
                    if let dVersion = try? await client.getDaemonVersion() {
                        if Task.isCancelled { return }
                        daemonVersion = dVersion
                        if let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                           dVersion != appVersion {
                            // Daemon binary changed (version bump). Since the daemon is already
                            // running and reachable, ask it to `launchctl kickstart -k` itself.
                            // This swaps the binary in-place without touching the SMAppService
                            // registration — avoids LWCR re-approval on macOS 26+.
                            logger.info("Daemon version mismatch (\(dVersion) vs app \(appVersion)). Restarting daemon in-place...")
                            try? await client.restartDaemon()
                            client.disconnect()        // drop stale connection; daemon is restarting
                            hasCheckedDaemonVersion = false
                            return
                        }
                    }
                }
                
                if Task.isCancelled { return }
                
                let viewingAll = isViewingAllSensors
                async let s = viewingAll ? client.readAllSensors() : client.readSensors()
                async let f = client.readFans()
                
                let fetchedSensors = try? await s
                if Task.isCancelled { return }
                
                let fetchedFans = try? await f
                if Task.isCancelled { return }
                
                if let fetchedSensors {
                    if viewingAll {
                        sensors = fetchedSensors
                        hasFullSensorSweep = true
                    } else {
                        // readSensors() only covers the active fan-curve driving groups, not
                        // the full sweep. A wholesale replace here would blow away the richer
                        // group data the Sensors tab just showed if isViewingAllSensors flips
                        // false mid-flight (e.g. the popover closes right as the Sensors tab's
                        // own viewer token registers) — so merge in place by sensor name instead
                        // of replacing the array.
                        var byName = Dictionary(uniqueKeysWithValues: sensors.map { ($0.name, $0) })
                        for reading in fetchedSensors { byName[reading.name] = reading }
                        sensors = Array(byName.values)
                    }
                }
                if let fetchedFans {
                    fans = fetchedFans
                }
            } else {
                let fallback = await Task.detached {
                    do {
                        let smc = try SMCController()
                        logger.info("SMCController init succeeded")
                        var s = (try? smc.readTemperatures()) ?? []
                        if let limits = try? smc.readLimits() {
                            s.append(contentsOf: limits)
                        }
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
                
                if Task.isCancelled { return }
                
                if !fallback.0.isEmpty { sensors = fallback.0 }
                if !fallback.1.isEmpty { fans = fallback.1 }
                activeProfile = .system
            }
            logger.info("Refresh complete. sensors=\(self.sensors.count) fans=\(self.fans.count)")
            lastSensorsUpdate = Date()
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
    
    // MARK: - Reordering
    
    func moveProfile(id: String, direction: Int) {
        var currentOrder = customProfiles.map(\.id)
        guard let index = currentOrder.firstIndex(of: id) else { return }
        
        let newIndex = index + direction
        guard newIndex >= 0 && newIndex < currentOrder.count else { return }
        
        currentOrder.swapAt(index, newIndex)
        UserDefaults.standard.set(currentOrder, forKey: "ProfileOrder")
        
        customProfiles.sort { a, b in
            let aIdx = currentOrder.firstIndex(of: a.id) ?? Int.max
            let bIdx = currentOrder.firstIndex(of: b.id) ?? Int.max
            if aIdx == bIdx { return a.id < b.id }
            return aIdx < bIdx
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

enum MenuBarItemLayout: String, CaseIterable {
    case horizontal
    case vertical

    var label: String { rawValue.capitalized }
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
