// DaemonXPCServer.swift
// Implements CoolMyMacXPCProtocol and manages the NSXPCListener lifecycle.

import Foundation
import SMCKit
import Security
import os.log

private let xpcLogger = Logger(subsystem: "com.coolmymac.daemon", category: "XPCServer")

let daemonVersionString = "1.0.2"

final class DaemonXPCServer: NSObject, NSXPCListenerDelegate {

    private let listener: NSXPCListener

    override init() {
        listener = NSXPCListener(machServiceName: CoolMyMacXPCServiceName)
        super.init()
        listener.delegate = self
    }

    func start() {
        listener.resume()
        ThermalController.shared.start()
        xpcLogger.info("XPC listener started on '\(CoolMyMacXPCServiceName, privacy: .public)'")
    }

    // MARK: NSXPCListenerDelegate

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        let pid = newConnection.processIdentifier
        let uid = effectiveUID(of: newConnection)

        // Tier 1: Always allow root. The daemon itself and privileged tools run as uid 0.
        if uid == 0 {
            xpcLogger.info("XPC connection accepted — root client (PID: \(pid, privacy: .public))")
            return accept(newConnection)
        }

        // Tier 2: Always allow our own signed application.
        if isOurSignedApp(newConnection) {
            xpcLogger.info("XPC connection accepted — trusted app (PID: \(pid, privacy: .public))")
            return accept(newConnection)
        }

        // Tier 3: Allow unprivileged CLI use if the user has opted in.
        // Setting stored in /Library/Preferences/com.coolmymac.daemon.plist — root-writable only.
        // Can be toggled from the app (via XPC → daemon) or via:
        //   sudo defaults write /Library/Preferences/com.coolmymac.daemon allowUnprivilegedCLI -bool YES
        let allowCLI = UserDefaults(suiteName: "com.coolmymac.daemon")?.bool(forKey: "allowUnprivilegedCLI") ?? false
        if allowCLI {
            xpcLogger.info("XPC connection accepted — unprivileged CLI (PID: \(pid, privacy: .public), UID: \(uid, privacy: .public))")
            return accept(newConnection)
        }

        // Denied — log a hint so it shows up in Console.app / unified logging.
        xpcLogger.warning("""
            XPC connection denied — unprivileged non-app client \
            (PID: \(pid, privacy: .public), UID: \(uid, privacy: .public)). \
            Use 'sudo coolmymac' or enable Allow Unprivileged CLI in CoolMyMac Preferences.
            """)
        return false
    }

    // MARK: - Private helpers
    
    nonisolated(unsafe) static var activeConnectionCount = 0
    static let connectionLock = NSLock()

    private func accept(_ connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: CoolMyMacXPCProtocol.self)
        connection.exportedObject = XPCHandler()
        
        DaemonXPCServer.connectionLock.lock()
        DaemonXPCServer.activeConnectionCount += 1
        xpcLogger.info("Client connected. Total clients: \(DaemonXPCServer.activeConnectionCount, privacy: .public)")
        DaemonXPCServer.connectionLock.unlock()
        
        connection.invalidationHandler = {
            DaemonXPCServer.connectionLock.lock()
            DaemonXPCServer.activeConnectionCount -= 1
            xpcLogger.info("Client disconnected. Total clients: \(DaemonXPCServer.activeConnectionCount, privacy: .public)")
            DaemonXPCServer.connectionLock.unlock()
            
            DaemonXPCServer.checkAutoSuspend()
        }
        
        connection.resume()
        return true
    }
    
    static func checkAutoSuspend() {
        DaemonXPCServer.connectionLock.lock()
        let count = DaemonXPCServer.activeConnectionCount
        DaemonXPCServer.connectionLock.unlock()
        
        let isSystemMode = ProfileStore.shared.getActiveProfile().curve.points.isEmpty
        if isSystemMode && count == 0 {
            xpcLogger.notice("Auto-suspending daemon: System profile active and 0 connected clients. launchd will automatically revive us when needed.")
            exit(0)
        }
    }

    /// Returns the effective UID of the connecting process.
    private func effectiveUID(of connection: NSXPCConnection) -> uid_t {
        return connection.effectiveUserIdentifier
    }

    /// Returns true if the connecting process is signed by our Developer team.
    /// The team ID is embedded in the code-signing requirement string below.
    /// Replace YOURTEAMID with your 10-character Apple Developer Team ID.
    private func isOurSignedApp(_ connection: NSXPCConnection) -> Bool {
        var code: SecCode?
        let attrs = [kSecGuestAttributePid: connection.processIdentifier] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attrs, [], &code) == errSecSuccess,
              let code else { return false }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
              let staticCode else { return false }

        // Matches any binary signed under your Developer ID Application certificate.
        let req = "anchor apple generic and certificate leaf[subject.OU] = \"G24X82SAVJ\""
        var reqRef: SecRequirement?
        guard SecRequirementCreateWithString(req as CFString, [], &reqRef) == errSecSuccess,
              let reqRef else { return false }

        return SecStaticCodeCheckValidity(staticCode, [], reqRef) == errSecSuccess
    }
}


// MARK: - XPC Handler

/// Handles XPC calls from clients (App, CLI). All methods run on the connection's private queue.
private final class XPCHandler: NSObject, CoolMyMacXPCProtocol {

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Version
    
    func getDaemonVersion(withReply reply: @escaping (String) -> Void) {
        reply(daemonVersionString)
    }

    // MARK: Sensors

    func readSensors(withReply reply: @escaping (Data?, Error?) -> Void) {
        let readings = ThermalController.shared.latestReadings
        encode(readings, reply: reply)
    }

    func readAllSensors(withReply reply: @escaping (Data?, Error?) -> Void) {
        let readings = ThermalController.shared.readAllSensors()
        encode(readings, reply: reply)
    }

    // MARK: Fans

    func readFans(withReply reply: @escaping (Data?, Error?) -> Void) {
        let fans = ThermalController.shared.latestFanStatus
        encode(fans, reply: reply)
    }

    // MARK: Profiles

    func activeProfile(withReply reply: @escaping (Data?, Error?) -> Void) {
        let profile = ProfileStore.shared.getActiveProfile()
        encode(profile, reply: reply)
    }

    func setActiveProfile(_ name: String, withReply reply: @escaping (Error?) -> Void) {
        do {
            try ProfileStore.shared.setActiveProfile(id: name)
            reply(nil)
            
            // Check if we just switched to System mode and should auto-suspend
            // We delay execution slightly so the reply makes it back to the client before we exit.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                DaemonXPCServer.checkAutoSuspend()
            }
        } catch {
            xpcLogger.error("setActiveProfile failed: \(error.localizedDescription, privacy: .public)")
            reply(error)
        }
    }

    func listProfiles(withReply reply: @escaping (Data?, Error?) -> Void) {
        let ids = ProfileStore.shared.listAllProfileIDs()
        encode(ids, reply: reply)
    }

    func getCustomProfiles(withReply reply: @escaping (Data?, Error?) -> Void) {
        let ids = ProfileStore.shared.listAllProfileIDs()
        let customProfiles = ids.compactMap { id -> FanProfile? in
            let profile = ProfileStore.shared.profile(named: id)
            return (profile?.isBuiltIn == false) ? profile : nil
        }
        encode(customProfiles, reply: reply)
    }

    func saveCustomProfile(_ profileData: Data, withReply reply: @escaping (Error?) -> Void) {
        do {
            let profile = try decoder.decode(FanProfile.self, from: profileData)
            try ProfileStore.shared.save(profile)
            reply(nil)
        } catch {
            xpcLogger.error("saveCustomProfile failed: \(error.localizedDescription, privacy: .public)")
            reply(error)
        }
    }

    func deleteCustomProfile(_ name: String, withReply reply: @escaping (Error?) -> Void) {
        do {
            try ProfileStore.shared.delete(id: name)
            reply(nil)
        } catch {
            xpcLogger.error("deleteCustomProfile failed: \(error.localizedDescription, privacy: .public)")
            reply(error)
        }
    }

    // MARK: Info

    func daemonVersion(withReply reply: @escaping (String) -> Void) {
        reply(daemonVersionString)
    }
    
    // MARK: Settings
    
    func setUpdateInterval(_ interval: Double, withReply reply: @escaping (Error?) -> Void) {
        UserDefaults(suiteName: "com.coolmymac.daemon")?.set(interval, forKey: "updateInterval")
        ThermalController.shared.setPollInterval(interval)
        reply(nil)
    }
    
    func getUpdateInterval(withReply reply: @escaping (Double, Error?) -> Void) {
        let saved = UserDefaults(suiteName: "com.coolmymac.daemon")?.double(forKey: "updateInterval") ?? 0
        let interval = saved == 0 ? 1.0 : saved
        reply(interval, nil)
    }

    // MARK: - Global Sensor Selection

    func setActiveSensors(_ groups: [String], excludedSensors: [String], withReply reply: @escaping (Error?) -> Void) {
        UserDefaults(suiteName: "com.coolmymac.daemon")?.set(groups, forKey: "activeSensors")
        UserDefaults(suiteName: "com.coolmymac.daemon")?.set(excludedSensors, forKey: "excludedSensors")
        reply(nil)
    }

    func getActiveSensors(withReply reply: @escaping ([String], [String], Error?) -> Void) {
        let savedGroups = UserDefaults(suiteName: "com.coolmymac.daemon")?.stringArray(forKey: "activeSensors") ?? [
            SensorGroup.cpuCore.rawValue, 
            SensorGroup.gpu.rawValue
        ]
        let savedExcluded = UserDefaults(suiteName: "com.coolmymac.daemon")?.stringArray(forKey: "excludedSensors") ?? []
        reply(savedGroups, savedExcluded, nil)
    }

    // MARK: - App Security Settings

    func setAllowUnprivilegedCLI(_ allow: Bool, withReply reply: @escaping (Error?) -> Void) {
        UserDefaults(suiteName: "com.coolmymac.daemon")?.set(allow, forKey: "allowUnprivilegedCLI")
        reply(nil)
    }

    func getAllowUnprivilegedCLI(withReply reply: @escaping (Bool, Error?) -> Void) {
        let saved = UserDefaults(suiteName: "com.coolmymac.daemon")?.bool(forKey: "allowUnprivilegedCLI") ?? false
        reply(saved, nil)
    }

    // MARK: Private

    private func encode<T: Encodable>(_ value: T, reply: @escaping (Data?, Error?) -> Void) {
        do {
            let data = try encoder.encode(value)
            reply(data, nil)
        } catch {
            reply(nil, error)
        }
    }
}
