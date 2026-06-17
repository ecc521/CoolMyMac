// ThermalController.swift
// Polls SMC sensors on a timer, applies the active profile's fan curve,
// and updates fan minimum RPMs via SMCController.
// Uses a rolling average (smoothing window) to prevent RPM hunting.

import Foundation
import SMCKit
import os.log
import IOKit
import IOKit.pwr_mgt

private let kIOMessageCanSystemSleep: UInt32 = 0xE0000270
private let kIOMessageSystemWillSleep: UInt32 = 0xE0000280
private let kIOMessageSystemHasPoweredOn: UInt32 = 0xE0000300

final class PowerMonitor {
    var rootPort: io_connect_t = 0
    var notifierObject: io_object_t = 0
    var notifyPortRef: IONotificationPortRef?

    func start() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        rootPort = IORegisterForSystemPower(context, &notifyPortRef, { (context, service, messageType, messageArgument) in
            guard let context = context else { return }
            let monitor = Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue()
            
            if messageType == kIOMessageCanSystemSleep || messageType == kIOMessageSystemWillSleep {
                ThermalController.shared.thermalLogger.notice("System going to sleep. Yielding fans to SMC.")
                ThermalController.shared.resetAllFansIfManaged()
                IOAllowPowerChange(monitor.rootPort, Int(bitPattern: messageArgument))
            } else if messageType == kIOMessageSystemHasPoweredOn {
                ThermalController.shared.thermalLogger.notice("System woke up. Resuming daemon control.")
            }
        }, &notifierObject)
        
        if rootPort != 0, let ref = notifyPortRef {
            IONotificationPortSetDispatchQueue(ref, DispatchQueue.main)
        }
    }
}

final class ThermalController: @unchecked Sendable {

    static let shared = ThermalController()
    
    let thermalLogger = Logger(subsystem: "com.coolmymac.daemon", category: "ThermalController")

    // How often we poll sensors (seconds)
    private var pollInterval: TimeInterval

    private var timer: DispatchSourceTimer?
    private var smcController: SMCController?
    private let powerMonitor = PowerMonitor()

    // Decaying EMA with hysteresis
    private var lastSmoothedTemp: Double = 0.0

    // Cached fan count — does not change at runtime on a given machine.
    // Read once at init and refreshed from the poll queue if needed.
    private var currentFanCount: Int = 0

    private let queue = DispatchQueue(label: "com.coolmymac.daemon.thermal", qos: .utility)

    private init() {
        let saved = UserDefaults(suiteName: "com.coolmymac.daemon")?.double(forKey: "updateInterval") ?? 0
        self.pollInterval = saved == 0 ? 1.0 : saved
        
        do {
            let controller = try SMCController()
            setup(with: controller)
            thermalLogger.notice("SUCCESS: SMCController initialized. Fan count: \(self.currentFanCount, privacy: .public)")
        } catch {
            setup(with: nil)
            thermalLogger.error("CRITICAL: Failed to initialize SMCController in daemon: \(error.localizedDescription, privacy: .public)")
        }

        powerMonitor.start()
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
        
        // Always reset fans to Apple auto control on boot, in case the daemon previously
        // crashed while fans were manually overridden, preventing them from being locked.
        resetAllFans()
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
    // All mutations happen on `queue`. Reads from other threads use stateLock.

    private let stateLock = NSLock()
    private var _latestReadings: [SensorReading] = []
    private var _latestFanStatus: [FanStatus] = []

    var latestReadings: [SensorReading] { 
        stateLock.lock()
        defer { stateLock.unlock() }
        return _latestReadings 
    }
    
    var latestFanStatus: [FanStatus] { 
        stateLock.lock()
        defer { stateLock.unlock() }
        return _latestFanStatus 
    }

    func readAllSensors() -> [SensorReading] {
        var allReadings = (try? smcController?.readTemperatures(for: nil)) ?? []
        if let limits = try? smcController?.readLimits() {
            allReadings.append(contentsOf: limits)
        }
        let advancedMetrics = MetricsService.shared.fetchPowerAndClocks()
        allReadings.append(contentsOf: advancedMetrics)
        return allReadings
    }

    private var isCurrentlyBackground: Bool = false
    private var currentActivity: NSObjectProtocol?
    
    private func updateProcessPriority(isSystemMode: Bool) {
        if isSystemMode && !isCurrentlyBackground {
            if let activity = currentActivity {
                ProcessInfo.processInfo.endActivity(activity)
                currentActivity = nil
            }
            // .background pushes the workload exclusively to E-cores
            currentActivity = ProcessInfo.processInfo.beginActivity(options: .background, reason: "CoolMyMac System Polling")
            isCurrentlyBackground = true
            thermalLogger.info("Downshifted daemon to background QoS (System Mode)")
        } else if !isSystemMode && isCurrentlyBackground {
            if let activity = currentActivity {
                ProcessInfo.processInfo.endActivity(activity)
                currentActivity = nil
            }
            // Release the background activity so it runs at the default .utility QoS of the DispatchQueue
            isCurrentlyBackground = false
            thermalLogger.info("Elevated daemon to utility QoS (Custom Mode)")
        }
    }

    // MARK: - Poll Cycle

    private func poll() {
        guard let smc = smcController else { return }

        let profile = ProfileStore.shared.getActiveProfile()
        let isSystemMode = profile.curve.points.isEmpty
        updateProcessPriority(isSystemMode: isSystemMode)

        // Read the sensor configuration once per tick (shared by the UI read below
        // and the fan-curve driving-temp calculation further down).
        let defaults = UserDefaults(suiteName: "com.coolmymac.daemon")
        let savedStrings = defaults?.stringArray(forKey: "activeSensors") ?? [
            SensorGroup.cpuCore.rawValue,
            SensorGroup.gpu.rawValue
        ]
        let savedExcluded = defaults?.stringArray(forKey: "excludedSensors") ?? []
        let globalSources = savedStrings.compactMap(SensorGroup.init(rawValue:))
        let activeGroups = globalSources.isEmpty ? [SensorGroup.cpuCore, .gpu] : globalSources
        let groupsToRead = Set(activeGroups)

        // Read sensors so the UI can display them even in System mode.
        // Hoisted out of the do/catch so the fan-control block can reuse it
        // instead of issuing a second (redundant) full SMC read.
        var latestReadings: [SensorReading] = []
        do {
            var readings = try smc.readTemperatures(for: groupsToRead)
            if groupsToRead.contains(.limits) {
                if let limits = try? smc.readLimits() {
                    readings.append(contentsOf: limits)
                }
            }
            latestReadings = readings
            stateLock.lock()
            _latestReadings = readings
            stateLock.unlock()
        } catch {
            thermalLogger.error("CRITICAL: readTemperatures failed: \(error.localizedDescription, privacy: .public)")
        }

        // Auto mode: do nothing with fan curves, but we still need to read fan status
        if isSystemMode {
            resetAllFansIfManaged()
            do {
                let allFans = try smc.readAllFans()
                let fanStatus = allFans.map { fan in
                    return FanStatus(id: fan.id, name: fan.name, currentRPM: fan.currentRPM,
                                     minRPM: fan.minRPM, maxRPM: fan.maxRPM, isManaged: false)
                }
                stateLock.lock()
                _latestFanStatus = fanStatus
                stateLock.unlock()
            } catch {
                thermalLogger.error("Thermal poll error: \(error.localizedDescription, privacy: .public)")
            }
            return
        }

        // Apply Fan Profile
        do {
            // Global override: Use activeSensors from UserDefaults instead of the profile's sources
            let settings = ProfileSettings(
                sources: activeGroups,
                excludedSensors: savedExcluded,
                aggregation: profile.settings.aggregation,
                spinUpTime: profile.settings.spinUpTime,
                spinDownTime: profile.settings.spinDownTime
            )

            // Reuse the readings already polled above for the UI; they cover exactly
            // the active sensor groups the curve aggregates over. Only fall back to a
            // fresh SMC read on the rare tick where the read above failed.
            let drivingTemp = latestReadings.isEmpty
                ? ((try? smc.drivingTemperature(for: settings)) ?? 0.0)
                : SMCController.drivingTemperature(from: latestReadings, settings: settings)
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
                    var targetRPM = Int(Double(fan.minRPM) + (range * targetPercentage))
                    
                    // If the curve evaluates to precisely 0%, attempt to shut the fan off completely.
                    // The SMC will internally clamp this to its safe hardware minimum if 0 RPM isn't supported.
                    if targetPercentage == 0.0 {
                        targetRPM = 0
                    } else if targetPercentage.isNaN {
                        // Failsafe against NaN math crashing the daemon integer cast
                        targetRPM = fan.minRPM
                    } else {
                        // Defensive clamp against potentially corrupted SMC reads or math overflow:
                        // Ensure we never write an RPM below the hardware min OR above the hardware max.
                        let safeMin = min(fan.minRPM, fan.maxRPM)
                        let safeMax = max(fan.minRPM, fan.maxRPM)
                        targetRPM = max(safeMin, min(safeMax, targetRPM))
                    }
                    
                    // Always enforce the profile's target RPM (Forced Mode).
                    // Yielding based on currentRPM causes infinite oscillation (thrashing)
                    // because actual RPM bounces around the target RPM.
                    try smc.setFanMinRPM(index: fan.id, rpm: targetRPM)
                    fansAreManaged = true
                }
            }

            // Read back and publish status for App/CLI UI updates
            let fanStatus = allFans.map { fan in
                return FanStatus(id: fan.id, name: fan.name, currentRPM: fan.currentRPM,
                                 minRPM: fan.minRPM, maxRPM: fan.maxRPM, isManaged: true)
            }
            stateLock.lock()
            _latestFanStatus = fanStatus
            stateLock.unlock()

        } catch {
            thermalLogger.error("Thermal poll error: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Temperature Aggregation (delegated to SMCController — see #10 DRY fix)

    // MARK: - Smoothing

    private func smooth(sample: Double, settings: ProfileSettings) -> Double {
        if lastSmoothedTemp == 0.0 {
            lastSmoothedTemp = sample
            return sample
        }
        
        func alpha(for time: TimeInterval) -> Double {
            if time <= 0 { return 1.0 }
            let periods = time / pollInterval
            return 2.0 / (periods + 1.0)
        }
        
        let isSpinUp = sample > lastSmoothedTemp
        
        if isSpinUp {
            let a = alpha(for: settings.spinUpTime)
            lastSmoothedTemp = (sample * a) + (lastSmoothedTemp * (1.0 - a))
        } else {
            // Hysteresis: Hold high water mark until it drops by at least 2.0°C
            let hysteresisBand = 2.0 
            if lastSmoothedTemp - sample > hysteresisBand {
                let a = alpha(for: settings.spinDownTime)
                lastSmoothedTemp = (sample * a) + (lastSmoothedTemp * (1.0 - a))
            }
        }
        
        return lastSmoothedTemp
    }

    // MARK: - Fan Reset

    private var fansAreManaged = false

    func resetAllFansIfManaged() {
        guard fansAreManaged else { return }
        resetAllFans()
    }

    private func resetAllFans() {
        guard let smc = smcController else { return }
        do {
            try smc.resetAllFans()
            fansAreManaged = false
            lastSmoothedTemp = 0.0
            thermalLogger.info("All fans reset to Apple auto")
        } catch {
            thermalLogger.error("Failed to reset fans: \(error.localizedDescription, privacy: .public)")
        }
    }
}
