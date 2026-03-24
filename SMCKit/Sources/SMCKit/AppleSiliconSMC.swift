// AppleSiliconSMC.swift
// Apple Silicon SMC backend placeholder — deferred to Phase 4.
// Will use IOHIDEventSystem when a test device is available (~10 days).

import Foundation

/// Apple Silicon SMC backend.
/// ⚠️ NOT IMPLEMENTED — Phase 4 work item.
/// Stub exists so SMCController can reference it in the backend selection logic.
final class AppleSiliconSMC: SMCProvider {

    init() throws {
        throw SMCError.unsupportedHardware
    }

    func readTemperatures() throws -> [SensorReading] { throw SMCError.unsupportedHardware }
    func readFan(index: Int) throws -> FanStatus { throw SMCError.unsupportedHardware }
    func fanCount() throws -> Int { throw SMCError.unsupportedHardware }
    func setFanMinRPM(index: Int, rpm: Int) throws { throw SMCError.unsupportedHardware }
    func resetFan(index: Int) throws { throw SMCError.unsupportedHardware }
}
