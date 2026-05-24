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
        
        do {
            let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
            guard let plist = plist else {
                return []
            }
            
            if let processor = plist["processor"] as? [String: Any] {
                let pkgW = (processor["combined_power"] as? Double ?? 0.0) / 1000.0
                let cpuW = (processor["cpu_power"] as? Double ?? 0.0) / 1000.0
                let gpuW = (processor["gpu_power"] as? Double ?? 0.0) / 1000.0
                
                readings.append(SensorReading(name: "Package Total", group: .power, value: pkgW, unit: .watts))
                readings.append(SensorReading(name: "CPU Core Total", group: .power, value: cpuW, unit: .watts))
                readings.append(SensorReading(name: "GPU Core Total", group: .power, value: gpuW, unit: .watts))
                
                let uncore = max(0, pkgW - cpuW - gpuW)
                if uncore > 0.01 {
                    readings.append(SensorReading(name: "System / Uncore", group: .power, value: uncore, unit: .watts))
                }
            }
            
            // Clock Speeds (MHz)
            if let processor = plist["processor"] as? [String: Any],
               let clusters = processor["clusters"] as? [[String: Any]] {
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
                            if let freqHz = firstCpu["freq_hz"] as? Double {
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
            }
            
            // GPU Clock
            if let gpu = plist["gpu"] as? [String: Any] {
                // Powermetrics sometimes outputs gpu freq_hz exactly in MHz, or sometimes Hz depending on macOS version.
                // In my manual test, gpu freq_hz was 338. So it's already in MHz!
                if let freq = gpu["freq_hz"] as? Double {
                    let mhz = freq > 1000000 ? freq / 1000000.0 : freq
                    readings.append(SensorReading(name: "GPU", group: .clockSpeed, value: mhz, unit: .megahertz))
                }
            }
            
        } catch {
            logger.error("Failed to parse powermetrics plist: \(error.localizedDescription)")
        }
        
        return readings
    }
}
