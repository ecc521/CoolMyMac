import Foundation
import os.log
import SMCKit

final class MetricsService: @unchecked Sendable {
    static let shared = MetricsService()
    private let logger = Logger(subsystem: "com.coolmymac.daemon", category: "MetricsService")
    
    private var cachedReadings: [SensorReading] = []
    private var isRunning = false
    private let queue = DispatchQueue(label: "com.coolmymac.daemon.metrics")
    private var buffer = Data()
    private var runningTask: Process?
    private var lastFetchTime = Date()
    private var shutdownTimer: DispatchSourceTimer?
    
    /// Starts the background powermetrics stream
    func start() {
        queue.async {
            guard !self.isRunning else { return }
            self.isRunning = true
            self.lastFetchTime = Date()
            
            let task = Process()
            self.runningTask = task
            task.executableURL = URL(fileURLWithPath: "/usr/bin/powermetrics")
            // Run continuously every 1000ms, unbuffered, with initial usage to eliminate start delay
            task.arguments = ["-i", "1000", "-b", "1", "--show-initial-usage", "--samplers", "cpu_power,gpu_power", "-f", "plist"]
            
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = FileHandle.nullDevice
            
            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else {
                    // EOF reached. Must set to nil to prevent 100% CPU infinite loop!
                    handle.readabilityHandler = nil
                    self?.queue.async { [weak self] in
                        self?.isRunning = false
                        self?.runningTask = nil
                    }
                    return
                }
                
                self?.queue.async { [weak self] in
                    self?.processIncomingData(data)
                }
            }
            
            do {
                try task.run()
                self.startShutdownTimer()
            } catch {
                self.logger.error("Failed to start powermetrics: \(error.localizedDescription)")
                self.isRunning = false
                self.runningTask = nil
            }
        }
    }
    
    private func startShutdownTimer() {
        shutdownTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 5.0, repeating: 5.0)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            // If no fetches for 5 seconds, spin down powermetrics
            if Date().timeIntervalSince(self.lastFetchTime) > 5.0 {
                self.logger.info("Spinning down powermetrics due to inactivity")
                self.runningTask?.terminate()
                self.runningTask = nil
                self.isRunning = false
                self.shutdownTimer?.cancel()
                self.shutdownTimer = nil
            }
        }
        timer.resume()
        shutdownTimer = timer
    }
    
    /// Fetch instantly from cache
    func fetchPowerAndClocks() -> [SensorReading] {
        queue.sync {
            lastFetchTime = Date()
        }
        if !isRunning { start() }
        return queue.sync { cachedReadings }
    }
    
    private func processIncomingData(_ data: Data) {
        buffer.append(data)
        
        // Trim leading garbage (like trailing \0 from previous chunks)
        if let startRange = buffer.range(of: "<?xml".data(using: .utf8)!) {
            if startRange.lowerBound > 0 {
                buffer.removeSubrange(0..<startRange.lowerBound)
            }
        } else {
            // Not enough data to even have a header yet
            return
        }
        
        // powermetrics dumps full plist files sequentially. Look for the end tag.
        guard let endTag = "</plist>\n".data(using: .utf8) else { return }
        
        while let range = buffer.range(of: endTag) {
            let chunk = buffer.subdata(in: 0..<range.upperBound)
            buffer.removeSubrange(0..<range.upperBound)
            
            if let readings = parsePowermetrics(data: chunk) {
                cachedReadings = readings
            }
            
            // Trim leading garbage for the NEXT chunk
            if let nextStart = buffer.range(of: "<?xml".data(using: .utf8)!) {
                if nextStart.lowerBound > 0 {
                    buffer.removeSubrange(0..<nextStart.lowerBound)
                }
            }
        }
    }
    
    private func parsePowermetrics(data: Data) -> [SensorReading]? {
        var readings: [SensorReading] = []
        
        func doubleValue(_ val: Any?) -> Double? {
            if let d = val as? Double { return d }
            if let i = val as? Int { return Double(i) }
            if let n = val as? NSNumber { return n.doubleValue }
            return nil
        }
        
        do {
            let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
            guard let plist = plist else {
                return []
            }
            
            if let processor = plist["processor"] as? [String: Any] {
                if let pkgWatts = doubleValue(processor["package_watts"]) {
                    // Intel format
                    readings.append(SensorReading(name: "Package Total", group: .power, value: pkgWatts, unit: .watts))
                } else {
                    // Apple Silicon format (combined_power, cpu_power, gpu_power are in mW)
                    let pkgW = (doubleValue(processor["combined_power"]) ?? 0.0) / 1000.0
                    let cpuW = (doubleValue(processor["cpu_power"]) ?? 0.0) / 1000.0
                    let gpuW = (doubleValue(processor["gpu_power"]) ?? 0.0) / 1000.0
                    
                    readings.append(SensorReading(name: "Package Total", group: .power, value: pkgW, unit: .watts))
                    readings.append(SensorReading(name: "CPU Core Total", group: .power, value: cpuW, unit: .watts))
                    readings.append(SensorReading(name: "GPU Core Total", group: .power, value: gpuW, unit: .watts))
                    
                    let uncore = max(0, pkgW - cpuW - gpuW)
                    if uncore > 0.01 {
                        readings.append(SensorReading(name: "System / Uncore", group: .power, value: uncore, unit: .watts))
                    }
                }
            }
            
            // Clock Speeds (MHz)
            if let processor = plist["processor"] as? [String: Any] {
                if let clusters = processor["clusters"] as? [[String: Any]] {
                    // Apple Silicon format
                    var totalCounts: [String: Int] = [:]
                    for cluster in clusters {
                        if let name = cluster["name"] as? String {
                            totalCounts[name, default: 0] += 1
                        }
                    }
                    
                    var currentCounts: [String: Int] = [:]
                    for cluster in clusters {
                        if let name = cluster["name"] as? String {
                            if let cpus = cluster["cpus"] as? [[String: Any]], let firstCpu = cpus.first {
                                if let freqHz = doubleValue(firstCpu["freq_hz"]) {
                                    currentCounts[name, default: 0] += 1
                                    let current = currentCounts[name, default: 0]
                                    let total = totalCounts[name, default: 0]
                                    
                                    let baseName = name.replacingOccurrences(of: "-Cluster", with: "")
                                    let displayName = total > 1 ? "\(baseName)\(current - 1)-CPU" : "\(baseName)-CPU"
                                    
                                    readings.append(SensorReading(name: displayName, group: .clockSpeed, value: freqHz / 1_000_000.0, unit: .megahertz))
                                }
                            }
                        }
                    }
                } else if let packages = processor["packages"] as? [[String: Any]] {
                    // Intel format
                    for package in packages {
                        if let cores = package["cores"] as? [[String: Any]] {
                            for core in cores {
                                if let coreId = core["core"] as? Int,
                                   let cpus = core["cpus"] as? [[String: Any]] {
                                    let freqs = cpus.compactMap { doubleValue($0["freq_hz"]) }
                                    if !freqs.isEmpty {
                                        let avgFreq = freqs.reduce(0.0, +) / Double(freqs.count)
                                        readings.append(SensorReading(
                                            name: "Core \(coreId)",
                                            group: .clockSpeed,
                                            value: avgFreq / 1_000_000.0,
                                            unit: .megahertz
                                        ))
                                    }
                                }
                            }
                        }
                    }
                    
                    // Overall CPU Total
                    if let freqHz = doubleValue(processor["freq_hz"]) {
                        readings.append(SensorReading(
                            name: "CPU Total",
                            group: .clockSpeed,
                            value: freqHz / 1_000_000.0,
                            unit: .megahertz
                        ))
                    }
                }
            }
            
            // GPU Clock
            if let gpuData = plist["gpu"] ?? plist["GPU"] {
                if let gpuDict = gpuData as? [String: Any] {
                    if let freq = doubleValue(gpuDict["freq_hz"]) {
                        let mhz = freq > 1000000 ? freq / 1000000.0 : freq
                        readings.append(SensorReading(name: "GPU", group: .clockSpeed, value: mhz, unit: .megahertz))
                    }
                } else if let gpuList = gpuData as? [[String: Any]] {
                    for item in gpuList {
                        let name = item["name"] as? String ?? "GPU"
                        if let freq = doubleValue(item["freq_hz"]) ?? doubleValue(item["freq_mhz"]) {
                            let mhz = freq > 1000000 ? freq / 1000000.0 : freq
                            let displayName = name == "GPU" ? name : "GPU (\(name))"
                            readings.append(SensorReading(name: displayName, group: .clockSpeed, value: mhz, unit: .megahertz))
                        }
                    }
                }
            }
            
        } catch {
            logger.error("Failed to parse powermetrics plist: \(error.localizedDescription)")
        }
        
        return readings
    }
}
