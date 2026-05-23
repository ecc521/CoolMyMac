// SMCController.swift
// Public facade for SMC access. Selects the correct backend based on hardware.
// This is the entry point for all SMC operations — consumers should use this, not backends directly.

import Foundation

// MARK: - SMCController

/// Public entry point for all SMC interactions.
/// Automatically selects the correct backend for the current hardware.
public final class SMCController {

    private let provider: SMCProvider

    #if DEBUG
    /// Internal initializer for dependency injection during unit tests.
    init(provider: SMCProvider) {
        self.provider = provider
    }
    #endif

    /// Initializes the controller, selecting the appropriate backend.
    /// - Throws: `SMCError.unsupportedHardware` if no suitable backend is available.
    public init() throws {
        self.provider = try AppleSiliconSMC()
    }

    // MARK: - Temperature

    /// All available temperature sensor readings, filtered to non-zero values.
    public func readTemperatures(for groups: Set<SensorGroup>? = nil) throws -> [SensorReading] {
        try provider.readTemperatures(for: groups)
    }

    // MARK: - Fan Control

    /// The number of physical fans in this system.
    public func fanCount() throws -> Int {
        try provider.fanCount()
    }

    /// Current status of a specific fan by index.
    public func readFan(index: Int) throws -> FanStatus {
        try provider.readFan(index: index)
    }

    /// Status of all fans.
    public func readAllFans() throws -> [FanStatus] {
        let count = try fanCount()
        return try (0..<count).map { try readFan(index: $0) }
    }

    /// Sets the minimum target RPM for a specific fan. Requires root.
    public func setFanMinRPM(index: Int, rpm: Int) throws {
        try provider.setFanMinRPM(index: index, rpm: rpm)
    }

    /// Resets a fan to Apple's automatic control.
    public func resetFan(index: Int) throws {
        try provider.resetFan(index: index)
    }

    /// Resets all fans to Apple's automatic control.
    public func resetAllFans() throws {
        let count = try fanCount()
        for i in 0..<count {
            try provider.resetFan(index: i)
        }
    }

    // MARK: - Aggregated Temperature (for profile-driven fan control)

    /// Returns the driving temperature for a given profile's settings,
    /// applying aggregation (MAX or AVERAGE) across the configured sensor groups.
    public func drivingTemperature(for settings: ProfileSettings) throws -> Double {
        let readings = try readTemperatures()
        let excluded = Set(settings.excludedSensors)
        let filtered = readings.filter { settings.sources.contains($0.group) && !excluded.contains($0.name) }

        guard !filtered.isEmpty else { return 0.0 }

        switch settings.aggregation {
        case .max:
            return filtered.map(\.value).max() ?? 0.0
        case .average:
            return filtered.map(\.value).reduce(0, +) / Double(filtered.count)
        }
    }
}
