// SMCProvider.swift
// Internal abstraction protocol for SMC backends.
// Allows swapping Intel (AppleSMC) and Apple Silicon (IOHIDEventSystem) backends.

import Foundation

// MARK: - Domain Errors

/// Errors surfaced by any SMCProvider implementation.
public enum SMCError: Error, LocalizedError {
    case deviceNotFound
    case keyNotFound(String)
    case readFailed(String)
    case writeFailed(String)
    case permissionDenied
    case unsupportedHardware

    public var errorDescription: String? {
        switch self {
        case .deviceNotFound:
            return "SMC device not found. This may be a virtual machine or unsupported hardware."
        case .keyNotFound(let key):
            return "SMC key not found: \(key)"
        case .readFailed(let key):
            return "Failed to read SMC key: \(key)"
        case .writeFailed(let key):
            return "Failed to write SMC key: \(key)"
        case .permissionDenied:
            return "SMC write access denied. Root privileges are required."
        case .unsupportedHardware:
            return "Hardware not supported by this backend."
        }
    }
}

// MARK: - SMCProvider Protocol

/// Internal protocol all SMC backends must conform to.
/// Not exposed publicly — consumers use `SMCController` instead.
protocol SMCProvider {
    /// Returns all available temperature sensor readings.
    func readTemperatures() throws -> [SensorReading]

    /// Returns the current status of a specific fan by index.
    func readFan(index: Int) throws -> FanStatus

    /// Returns the number of physical fans in the system.
    func fanCount() throws -> Int

    /// Sets the minimum target RPM for a specific fan.
    /// - Requires root (daemon) privileges.
    func setFanMinRPM(index: Int, rpm: Int) throws

    /// Resets a fan to Apple's automatic control.
    func resetFan(index: Int) throws
}
