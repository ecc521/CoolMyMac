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
    private var pollInterval: TimeInterval

    private var timer: DispatchSourceTimer?
    private var smcController: SMCController?

    // Rolling temperature samples per fan, used for smoothing
    private var temperatureSamples: [Double] = []

    // Cached fan count — does not change at runtime on a given machine.
    // Read once at init and refreshed from the poll queue if needed.
    private var currentFanCount: Int = 0

    private let queue = DispatchQueue(label: "com.coolmymac.daemon.thermal", qos: .userInitiated)

    private init() {
        let saved = UserDefaults.standard.double(forKey: "updateInterval")
        self.pollInterval = saved == 0 ? 1.0 : saved
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
    
    func setPollInterval(_ interval: TimeInterval) {
        guard self.pollInterval != interval else { return }
        self.pollInterval = interval
        if timer != nil {
            stop()
            start()
        }
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

            // Global override: Use activeSensors from UserDefaults instead of the profile's sources
            let savedStrings = UserDefaults.standard.stringArray(forKey: "activeSensors") ?? [
                SensorGroup.cpuCore.rawValue, 
                SensorGroup.gpu.rawValue
            ]
            let globalSources = savedStrings.compactMap(SensorGroup.init(rawValue:))
            
            let settings = ProfileSettings(
                sources: globalSources.isEmpty ? [.cpuCore, .gpu] : globalSources,
                aggregation: profile.settings.aggregation,
                spinUpTime: profile.settings.spinUpTime,
                spinDownTime: profile.settings.spinDownTime
            )

            let drivingTemp = (try? smc.drivingTemperature(for: settings)) ?? 0.0
            let smoothedTemp = smooth(sample: drivingTemp, settings: profile.settings)
            let targetPercentage = profile.curve.targetPercentage(for: smoothedTemp)

            thermalLogger.debug("Driving temp: \(drivingTemp, privacy: .public)°C smoothed: \(smoothedTemp, privacy: .public)°C → target: \(Int(targetPercentage * 100), privacy: .public)%")

            // Read fan boundaries from SMC to calculate target RPM per-fan based on percentage
            let allFans = try smc.readAllFans()

            // Apply calculated RPM per fan
            for fan in allFans {
                if profile.curve.points.isEmpty {
                    // Yield control back to Apple SMC
                    if fansAreManaged {
                        try? smc.resetFan(index: fan.id)
                    }
                } else {
                    let range = Double(fan.maxRPM - fan.minRPM)
                    let targetRPM = Int(Double(fan.minRPM) + (range * targetPercentage))
                    try smc.setFanMinRPM(index: fan.id, rpm: targetRPM)
                }
            }
            
            fansAreManaged = !profile.curve.points.isEmpty

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

    // MARK: - Smoothing

    private func smooth(sample: Double, settings: ProfileSettings) -> Double {
        let currentAverage = temperatureSamples.isEmpty 
            ? sample 
            : temperatureSamples.reduce(0, +) / Double(temperatureSamples.count)
            
        let isSpinUp = sample > currentAverage
        let windowSeconds = isSpinUp ? settings.spinUpTime : settings.spinDownTime
        let windowSamples = max(1, Int(windowSeconds / pollInterval))
        
        if isSpinUp && windowSamples <= 1 {
            // Fast spin-up: If the new reading is hotter than the average,
            // fast-forward the buffer to immediately apply the highest temperature.
            temperatureSamples = Array(repeating: sample, count: windowSamples)
        } else {
            // Smoothly average the changes
            temperatureSamples.append(sample)
            if temperatureSamples.count > windowSamples {
                temperatureSamples.removeFirst(temperatureSamples.count - windowSamples)
            }
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
