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

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .localDomainMask).first
            ?? URL(fileURLWithPath: "/Library/Application Support")
        profilesURL = appSupport.appendingPathComponent("CoolMyMac/profiles", isDirectory: true)
        try? FileManager.default.createDirectory(at: profilesURL, withIntermediateDirectories: true)
    }

    // MARK: - Active Profile

    private var activeProfileID: String {
        get {
            UserDefaults(suiteName: "com.coolmymac.daemon")?.string(forKey: "activeProfileID") ?? "balanced"
        }
        set {
            UserDefaults(suiteName: "com.coolmymac.daemon")?.set(newValue, forKey: "activeProfileID")
        }
    }

    func getActiveProfile() -> FanProfile {
        let id = activeProfileID
        return profile(named: id) ?? .balanced
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
        // Load from disk
        return loadCustomProfile(id: id)
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
        let data = try JSONEncoder().encode(profile)
        let url = profileURL(for: profile.id)
        try data.write(to: url, options: .atomic)
        profileLogger.info("Saved custom profile '\(profile.id, privacy: .public)'")
    }

    func delete(id: String) throws {
        guard !FanProfile.allBuiltIn.contains(where: { $0.id == id }) else {
            throw ProfileStoreError.cannotModifyBuiltIn(id)
        }
        let url = profileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ProfileStoreError.profileNotFound(id)
        }
        try FileManager.default.removeItem(at: url)
        // If we just deleted the active profile, fall back to balanced
        if activeProfileID == id { activeProfileID = "balanced" }
        profileLogger.info("Deleted custom profile '\(id, privacy: .public)'")
    }

    // MARK: - Private Helpers

    private func profileURL(for id: String) -> URL {
        profilesURL.appendingPathComponent("\(id).json")
    }

    private func loadCustomProfile(id: String) -> FanProfile? {
        let url = profileURL(for: id)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(FanProfile.self, from: data)
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

    var errorDescription: String? {
        switch self {
        case .profileNotFound(let id):    return "Profile not found: \(id)"
        case .cannotModifyBuiltIn(let id): return "Cannot modify built-in profile: \(id)"
        }
    }
}
