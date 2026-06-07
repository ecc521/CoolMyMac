// SMCProvider.swift
// Internal abstraction protocol for SMC backends.

import Foundation

// MARK: - Domain Errors

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

public protocol SMCProvider {
    func readTemperatures(for groups: Set<SensorGroup>?) throws -> [SensorReading]
    func readLimits() throws -> [SensorReading]
    func readFan(index: Int) throws -> FanStatus
    func fanCount() throws -> Int
    func setFanMinRPM(index: Int, rpm: Int) throws
    func resetFan(index: Int) throws
}
