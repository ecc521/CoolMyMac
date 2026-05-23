// CoolMyMacXPCProtocol.swift
// Shared XPC protocol — must use only ObjC-compatible types.
// Hosted in SMCKit so Daemon, App, and CLI all share the same contract.

import Foundation

/// The XPC protocol between CoolMyMac-App/CLI and CoolMyMac-Daemon.
/// All methods use callback-style withReply patterns (ObjC-compatible).
@objc public protocol CoolMyMacXPCProtocol {

    // MARK: - Version Check
    
    /// Returns the internal version string of the daemon bundle (e.g. "1.0.0")
    func getDaemonVersion(withReply reply: @escaping (String) -> Void)

    // MARK: - Sensor Readings

    /// Returns JSON-encoded array of `SensorReading` for all active sensors.
    func readSensors(withReply reply: @escaping (Data?, Error?) -> Void)

    /// Returns JSON-encoded array of `SensorReading` structs. (Full sensor sweep, slow)
    func readAllSensors(withReply reply: @escaping (Data?, Error?) -> Void)

    /// Returns JSON-encoded array of `FanStatus` for all physical fans.
    func readFans(withReply reply: @escaping (Data?, Error?) -> Void)

    // MARK: - Profile Management

    /// Returns JSON-encoded `FanProfile` for the currently active profile.
    func activeProfile(withReply reply: @escaping (Data?, Error?) -> Void)

    /// Sets the active profile by name. Built-in names: "quiet", "balanced", "performance", "max".
    /// Custom profile names are user-defined.
    func setActiveProfile(_ name: String, withReply reply: @escaping (Error?) -> Void)

    /// Returns JSON-encoded array of all `FanProfile` names (built-in + custom).
    func listProfiles(withReply reply: @escaping (Data?, Error?) -> Void)
    
    /// Returns JSON-encoded array of `FanProfile` structs for all custom profiles.
    func getCustomProfiles(withReply reply: @escaping (Data?, Error?) -> Void)

    /// Saves (or replaces) a custom profile. Accepts JSON-encoded `FanProfile`.
    func saveCustomProfile(_ profileData: Data, withReply reply: @escaping (Error?) -> Void)

    /// Deletes a custom profile by name. Returns an error if it's a built-in profile.
    func deleteCustomProfile(_ name: String, withReply reply: @escaping (Error?) -> Void)

    // MARK: - Daemon Info

    /// Returns the daemon's version string.
    func daemonVersion(withReply reply: @escaping (String) -> Void)
    
    /// Sets the thermal polling interval for the background daemon. (Seconds)
    func setUpdateInterval(_ interval: Double, withReply reply: @escaping (Error?) -> Void)
    
    /// Gets the current thermal polling interval from the daemon.
    func getUpdateInterval(withReply reply: @escaping (Double, Error?) -> Void)

    // MARK: - Global Sensor Selection

    /// Sets the active sensor groups used for aggregation by the daemon, and any specific sensors to exclude.
    func setActiveSensors(_ groups: [String], excludedSensors: [String], withReply reply: @escaping (Error?) -> Void)

    /// Gets the current active sensor groups and excluded sensors from the daemon.
    func getActiveSensors(withReply reply: @escaping ([String], [String], Error?) -> Void)

    // MARK: - App Security Settings

    /// Toggles whether unprivileged terminal sessions can issue commands to the daemon.
    func setAllowUnprivilegedCLI(_ allow: Bool, withReply reply: @escaping (Error?) -> Void)

    /// Retrieves the current unprivileged terminal execution policy.
    func getAllowUnprivilegedCLI(withReply reply: @escaping (Bool, Error?) -> Void)
}

/// Mach service name for XPC — must match the daemon's Info.plist MachServices entry.
public let CoolMyMacXPCServiceName = "com.coolmymac.app.daemon"
