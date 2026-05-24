// ProfileStore.swift
// Manages reading and writing of FanProfile JSON files.
// Built-in profiles are always available; custom profiles live in Application Support.

import Foundation
import SMCKit
import os.log

private let profileLogger = Logger(subsystem: "com.coolmymac.daemon", category: "ProfileStore")

final class ProfileStore: @unchecked Sendable {

    static let shared = ProfileStore()

    private let profilesURL: URL
    private let cacheLock = NSLock()
    private var profileCache: [String: FanProfile] = [:]
    private var _cachedActiveProfileID: String?

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .localDomainMask).first
            ?? URL(fileURLWithPath: "/Library/Application Support")
        profilesURL = appSupport.appendingPathComponent("CoolMyMac/profiles", isDirectory: true)
        try? FileManager.default.createDirectory(at: profilesURL, withIntermediateDirectories: true)
        
        for template in FanProfile.defaultTemplates {
            if loadCustomProfile(id: template.id) == nil {
                let url = profileURL(for: template.id)
                if let data = try? JSONEncoder().encode(template) {
                    try? data.write(to: url, options: .atomic)
                }
            }
        }
    }

    // MARK: - Active Profile

    private var activeProfileID: String {
        get {
            cacheLock.lock()
            if let cached = _cachedActiveProfileID {
                cacheLock.unlock()
                return cached
            }
            cacheLock.unlock()
            
            let txtURL = profilesURL.deletingLastPathComponent().appendingPathComponent("active_profile.txt")
            let disk = (try? String(contentsOf: txtURL, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "system"
            let finalDisk = disk.isEmpty ? "system" : disk
            
            cacheLock.lock()
            _cachedActiveProfileID = finalDisk
            cacheLock.unlock()
            return finalDisk
        }
        set {
            cacheLock.lock()
            _cachedActiveProfileID = newValue
            cacheLock.unlock()
            
            let txtURL = profilesURL.deletingLastPathComponent().appendingPathComponent("active_profile.txt")
            try? newValue.write(to: txtURL, atomically: true, encoding: .utf8)
        }
    }

    func getActiveProfile() -> FanProfile {
        let id = activeProfileID
        return profile(named: id) ?? .system
    }

    func setActiveProfile(id: String) throws {
        guard profile(named: id) != nil else {
            throw ProfileStoreError.profileNotFound(id)
        }
        activeProfileID = id
        profileLogger.info("Active profile changed to '\(id, privacy: .public)'")
    }

    // MARK: - Lookup

    func profile(named id: String) -> FanProfile? {
        // Check built-ins first
        if let builtin = FanProfile.allBuiltIn.first(where: { $0.id == id }) {
            return builtin
        }
        
        // Fast path: memory cache
        cacheLock.lock()
        if let cached = profileCache[id] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        // Slow path: load from disk and cache
        if let loaded = loadCustomProfile(id: id) {
            cacheLock.lock()
            profileCache[id] = loaded
            cacheLock.unlock()
            return loaded
        }
        
        return nil
    }

    func listAllProfileIDs() -> [String] {
        let builtInIDs = FanProfile.allBuiltIn.map(\.id)
        let customIDs = loadCustomProfileIDs()
        return builtInIDs + customIDs
    }

    // MARK: - Custom Profile Persistence

    func save(_ profile: FanProfile) throws {
        guard !profile.isBuiltIn else {
            throw ProfileStoreError.cannotModifyBuiltIn(profile.id)
        }
        try profile.validate()
        let data = try JSONEncoder().encode(profile)
        let url = profileURL(for: profile.id)
        try data.write(to: url, options: .atomic)
        
        // Update cache synchronously
        cacheLock.lock()
        profileCache[profile.id] = profile
        cacheLock.unlock()
        
        profileLogger.info("Saved custom profile '\(profile.id, privacy: .public)'")
    }

    func delete(id: String) throws {
        guard !FanProfile.allBuiltIn.contains(where: { $0.id == id }) else {
            throw ProfileStoreError.cannotModifyBuiltIn(id)
        }
        try validateProfileID(id)
        let url = profileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ProfileStoreError.profileNotFound(id)
        }
        try FileManager.default.removeItem(at: url)
        
        cacheLock.lock()
        profileCache.removeValue(forKey: id)
        cacheLock.unlock()
        
        // If we just deleted the active profile, fall back to system
        if activeProfileID == id { activeProfileID = "system" }
        profileLogger.info("Deleted custom profile '\(id, privacy: .public)'")
    }

    // MARK: - Private Helpers

    /// Validates a profile ID is safe to use as a filename component.
    /// Allows alphanumeric characters, hyphens, and underscores; max 64 chars.
    /// This prevents path traversal attacks (e.g. "../../etc/evil").
    private func validateProfileID(_ id: String) throws {
        guard !id.isEmpty, id.count <= 64 else {
            throw ProfileStoreError.invalidProfileID(id)
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard id.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw ProfileStoreError.invalidProfileID(id)
        }
    }

    private func profileURL(for id: String) -> URL {
        profilesURL.appendingPathComponent("\(id).json")
    }

    private func loadCustomProfile(id: String) -> FanProfile? {
        let url = profileURL(for: id)
        guard let data = try? Data(contentsOf: url),
              let loaded = try? JSONDecoder().decode(FanProfile.self, from: data) else {
            return nil
        }
        
        do {
            try loaded.validate()
            return loaded
        } catch {
            profileLogger.error("Profile '\(id, privacy: .public)' failed validation: \(error.localizedDescription, privacy: .public). Falling back.")
            return nil
        }
    }

    private func loadCustomProfileIDs() -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(at: profilesURL, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }
}

// MARK: - Errors

enum ProfileStoreError: Error, LocalizedError {
    case profileNotFound(String)
    case cannotModifyBuiltIn(String)
    case invalidProfileID(String)

    var errorDescription: String? {
        switch self {
        case .profileNotFound(let id):     return "Profile not found: \(id)"
        case .cannotModifyBuiltIn(let id): return "Cannot modify built-in profile: \(id)"
        case .invalidProfileID(let id):    return "Invalid profile ID '\(id)': must be alphanumeric with hyphens/underscores, max 64 chars."
        }
    }
}
