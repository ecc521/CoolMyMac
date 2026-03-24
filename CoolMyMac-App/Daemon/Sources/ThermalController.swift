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

    // Cached fan count — does not change at runtime on a given machine.
    // Read once at init and refreshed from the poll queue if needed.
    private var currentFanCount: Int = 0

    private let queue = DispatchQueue(label: "com.coolmymac.daemon.thermal", qos: .userInitiated)

    private init() {
        setup(with: try? SMCController())
    }

    #if DEBUG
    /// Allows injecting a mock controller for unit testing.
    func inject(controller: SMCController?) {
        setup(with: controller)
    }
    #endif

    private func setup(with controller: SMCController?) {
        self.smcController = controller
        self.currentFanCount = (try? smcController?.fanCount()) ?? 0
        thermalLogger.info("ThermalController initialized. Fan count: \(self.currentFanCount, privacy: .public)")
    }

    // MARK: - Lifecycle

    func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: pollInterval)
        t.setEventHandler { [weak self] in self?.poll() }
        t.resume()
        timer = t
        thermalLogger.info("Thermal polling started (interval: \(self.pollInterval, privacy: .public)s)")
    }

    func stop() {
        timer?.cancel()
        timer = nil
        resetAllFans()
        thermalLogger.info("Thermal polling stopped. Fans reset to Auto.")
    }

    // MARK: - Latest Readings (thread-safe snapshot for XPC reads)
    // All mutations happen on `queue`. Reads from other threads use queue.sync.

    private var _latestReadings: [SensorReading] = []
    private var _latestFanStatus: [FanStatus] = []

    var latestReadings: [SensorReading] { queue.sync { _latestReadings } }
    var latestFanStatus: [FanStatus]    { queue.sync { _latestFanStatus } }

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
            _latestReadings = readings

            let drivingTemp = (try? smc.drivingTemperature(for: profile.settings)) ?? 0.0
            let smoothedTemp = smooth(sample: drivingTemp, windowSeconds: profile.settings.smoothingWindowSeconds)
            let targetPercentage = profile.curve.targetPercentage(for: smoothedTemp)

            thermalLogger.debug("Driving temp: \(drivingTemp, privacy: .public)°C smoothed: \(smoothedTemp, privacy: .public)°C → target: \(Int(targetPercentage * 100), privacy: .public)%")

            // Read fan boundaries from SMC to calculate target RPM per-fan based on percentage
            let allFans = try smc.readAllFans()

            // Apply calculated RPM per fan
            for fan in allFans {
                let range = Double(fan.maxRPM - fan.minRPM)
                let targetRPM = Int(Double(fan.minRPM) + (range * targetPercentage))
                try smc.setFanMinRPM(index: fan.id, rpm: targetRPM)
            }
            fansAreManaged = true  // #4: mark fans as under CoolMyMac control

            // Read back and publish status for App/CLI UI updates
            _latestFanStatus = allFans.map { fan in
                let range = Double(fan.maxRPM - fan.minRPM)
                let pct = (Double(fan.currentRPM) - Double(fan.minRPM)) / range
                return FanStatus(id: fan.id, name: fan.name, currentRPM: fan.currentRPM,
                                 minRPM: fan.minRPM, maxRPM: fan.maxRPM, isManaged: true)
            }

        } catch {
            thermalLogger.error("Thermal poll error: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Temperature Aggregation (delegated to SMCController — see #10 DRY fix)

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
            thermalLogger.info("All fans reset to Apple auto")
        } catch {
            thermalLogger.error("Failed to reset fans: \(error.localizedDescription, privacy: .public)")
        }
    }
}
