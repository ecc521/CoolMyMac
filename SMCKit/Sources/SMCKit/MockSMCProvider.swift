// MockSMCProvider.swift
// A completely synthetic SMC Backend for unit tests.

import Foundation

public final class MockSMCProvider: SMCProvider, @unchecked Sendable {
    public var mockedSensors: [SensorReading] = []
    public var mockedFans: [FanStatus] = []

    public var setFanMinRPMLog: [(index: Int, rpm: Int)] = []
    public var resetFanLog: [Int] = []

    public var shouldThrowError: SMCError?

    public init() {}

    public func readTemperatures() throws -> [SensorReading] {
        if let error = shouldThrowError { throw error }
        return mockedSensors
    }

    public func readFan(index: Int) throws -> FanStatus {
        if let error = shouldThrowError { throw error }
        guard let fan = mockedFans.first(where: { $0.id == index }) else {
            throw SMCError.deviceNotFound
        }
        return fan
    }

    public func readAllFans() throws -> [FanStatus] {
        if let error = shouldThrowError { throw error }
        return mockedFans
    }

    public func fanCount() throws -> Int {
        if let error = shouldThrowError { throw error }
        return mockedFans.count
    }

    public func setFanMinRPM(index: Int, rpm: Int) throws {
        if let error = shouldThrowError { throw error }
        setFanMinRPMLog.append((index, rpm))
        if let i = mockedFans.firstIndex(where: { $0.id == index }) {
            let f = mockedFans[i]
            mockedFans[i] = FanStatus(id: f.id, name: f.name, currentRPM: f.currentRPM,
                                      minRPM: rpm, maxRPM: f.maxRPM, isManaged: true)
        }
    }

    public func resetFan(index: Int) throws {
        if let error = shouldThrowError { throw error }
        resetFanLog.append(index)
        if let i = mockedFans.firstIndex(where: { $0.id == index }) {
            let f = mockedFans[i]
            mockedFans[i] = FanStatus(id: f.id, name: f.name, currentRPM: f.currentRPM,
                                      minRPM: 0, maxRPM: f.maxRPM, isManaged: false)
        }
    }
}
