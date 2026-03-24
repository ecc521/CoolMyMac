// ThermalController.swift
// Polls SMC sensors on a timer, applies the active profile's fan curve,
// and updates fan minimum RPMs via SMCController.
// Uses a rolling average (smoothing window) to prevent RPM hunting.

import Foundation
import SMCKit
import os.log

private let thermalLogger = Logger(subsystem: "com.coolmymac.daemon", category: "ThermalController")

final class ThermalController: @unchecked Sendable {

    static let shared = ThermalController()

    // How often we poll sensors (seconds)
    private let pollInterval: TimeInterval = 2.0

    private var timer: DispatchSourceTimer?
    private var smcController: SMCController?

    // Rolling temperature samples per fan, used for smoothing
    private var temperatureSamples: [Double] = []
    private var currentFanCount: Int = 0

    private let queue = DispatchQueue(label: "com.coolmymac.daemon.thermal", qos: .userInitiated)

    private init() {
        do {
            smcController = try SMCController()
            currentFanCount = (try? smcController?.fanCount()) ?? 0
            thermalLogger.info("ThermalController initialized. Fan count: \(self.currentFanCount, privacy: .public)")
        } catch {
            thermalLogger.error("ThermalController failed to initialize SMCController: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Lifecycle

    func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: pollInterval)
        t.setEventHandler { [weak self] in self?.poll() }
        t.resume()
        timer = t
        logger.info("Thermal polling started (interval: \(self.pollInterval, privacy: .public)s)")
    }

    func stop() {
        timer?.cancel()
        timer = nil
        resetAllFans()
        logger.info("Thermal polling stopped. Fans reset to Auto.")
    }

    // MARK: - Latest Readings (thread-safe snapshot for XPC reads)

    private(set) var latestReadings: [SensorReading] = []
    private(set) var latestFanStatus: [FanStatus] = []

    // MARK: - Poll Cycle

    private func poll() {
        guard let smc = smcController else { return }

        let profile = ProfileStore.shared.getActiveProfile()

        // Auto mode: do nothing, Apple manages fans
        guard !profile.curve.points.isEmpty else {
            resetAllFansIfManaged()
            return
        }

        // Read sensors
        do {
            let readings = try smc.readTemperatures()
            latestReadings = readings

            let drivingTemp = aggregate(readings: readings, settings: profile.settings)
            let smoothedTemp = smooth(sample: drivingTemp, windowSeconds: profile.settings.smoothingWindowSeconds)
            let targetRPM = profile.curve.targetRPM(for: smoothedTemp)

            thermalLogger.debug("Driving temp: \(drivingTemp, privacy: .public)°C smoothed: \(smoothedTemp, privacy: .public)°C → target: \(targetRPM, privacy: .public) RPM")

            // Apply to all fans
            let count = try smc.fanCount()
            for i in 0..<count {
                try smc.setFanMinRPM(index: i, rpm: targetRPM)
            }

            // Read back fan status for XPC clients
            latestFanStatus = (try? smc.readAllFans().map { fan in
                FanStatus(id: fan.id, name: fan.name, currentRPM: fan.currentRPM,
                         minRPM: fan.minRPM, maxRPM: fan.maxRPM, isManaged: true)
            }) ?? []

        } catch {
            thermalLogger.error("Thermal poll error: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Temperature Aggregation

    private func aggregate(readings: [SensorReading], settings: ProfileSettings) -> Double {
        let filtered = readings.filter { settings.sources.contains($0.group) }
        guard !filtered.isEmpty else { return 0.0 }

        switch settings.aggregation {
        case .max:     return filtered.map(\.celsius).max() ?? 0.0
        case .average: return filtered.map(\.celsius).reduce(0, +) / Double(filtered.count)
        }
    }

    // MARK: - Smoothing (rolling average over N samples)

    private func smooth(sample: Double, windowSeconds: Double) -> Double {
        let windowSamples = max(1, Int(windowSeconds / pollInterval))
        temperatureSamples.append(sample)
        if temperatureSamples.count > windowSamples {
            temperatureSamples.removeFirst(temperatureSamples.count - windowSamples)
        }
        return temperatureSamples.reduce(0, +) / Double(temperatureSamples.count)
    }

    // MARK: - Fan Reset

    private var fansAreManaged = false

    private func resetAllFansIfManaged() {
        guard fansAreManaged else { return }
        resetAllFans()
    }

    private func resetAllFans() {
        guard let smc = smcController else { return }
        do {
            try smc.resetAllFans()
            fansAreManaged = false
            temperatureSamples.removeAll()
            logger.info("All fans reset to Apple auto")
        } catch {
            logger.error("Failed to reset fans: \(error.localizedDescription, privacy: .public)")
        }
    }
}
