// TempsCommand.swift
// `coolmymac temps` — lists all temperature readings.

import ArgumentParser
import Foundation
import SMCKit

struct TempsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "temps",
        abstract: "Display current temperature sensor readings"
    )

    @Flag(name: .shortAndLong, help: "Show only sensors above a threshold (°C)")
    var hot: Bool = false

    @Option(name: .long, help: "Minimum temperature threshold in °C (implies --hot). Default is 60.0 when --hot is passed.")
    var threshold: Double?

    @Flag(name: .shortAndLong, help: "Show all sensors including OTHER group")
    var all: Bool = false

    @Flag(name: .long, help: "Output raw JSON")
    var json: Bool = false

    mutating func run() async throws {
        let result = await CLIContext.readSensors(all: all)

        switch result {
        case .failure(let err):
            fputs(err.message + "\n", stderr)
            throw ExitCode.failure

        case .success(let readings):
            var filtered = all ? readings : readings.filter { $0.group != .other }
            
            let filterThreshold = threshold ?? (hot ? 60.0 : nil)
            if let t = filterThreshold {
                filtered = filtered.filter { $0.value >= t }
            }

            if json {
                let data = try JSONEncoder().encode(filtered)
                print(String(decoding: data, as: UTF8.self))
                return
            }

            if filtered.isEmpty {
                print("No sensor readings available.")
                return
            }

            // Group by sensor group (Labeled by Architecture Support):
            // - .power: Both (Intel: package_watts; Apple Silicon: combined/cpu/gpu mW)
            // - .clockSpeed: Both (Intel: core/package/GPU freqs; Apple Silicon: cluster/GPU freqs)
            // - .cpuCore: Both (Intel: TCxx keys; Apple Silicon: Tpxx/cores)
            // - .gpu: Both (Intel: TGxx keys; Apple Silicon: Tgxx/GPU core)
            // - .vrm: Both (Intel: TPCD/Power/PCH; Apple Silicon: VRM keys)
            // - .wireless: Intel-only (TWxx wifi keys)
            // - .battery: Both (Intel: TBxx keys; Apple Silicon: TBxx keys)
            // - .enclosure: Both (Intel: heatsink/ambient/skin; Apple Silicon: skin/ambient)
            // - .nand: Both (Intel: TNxx keys; Apple Silicon: Tnxx keys)
            // - .other: Both
            let grouped = Dictionary(grouping: filtered, by: \.group)
            let order: [SensorGroup] = [.power, .clockSpeed, .cpuCore, .gpu, .vrm, .wireless, .battery, .enclosure, .nand, .other]

            for group in order {
                guard let sensors = grouped[group], !sensors.isEmpty else { continue }
                print("\n\(group.displayName)")
                print(String(repeating: "─", count: 30))
                for sensor in sensors.sorted(by: { $0.value > $1.value }) {
                    let formattedValue: String
                    let bar: String
                    let arrow: String
                    
                    switch sensor.unit {
                    case .celsius:
                        formattedValue = String(format: "%5.1f°C", sensor.value)
                        bar = thermalBar(celsius: sensor.value)
                        arrow = sensor.value >= 80 ? " ⚠️" : ""
                    case .watts:
                        formattedValue = String(format: "%5.2f W", sensor.value)
                        bar = ""
                        arrow = ""
                    case .megahertz:
                        formattedValue = String(format: "%5.0f MHz", sensor.value)
                        bar = ""
                        arrow = ""
                    }
                    
                    print(String(format: "  %-20@  %@  %@%@",
                          sensor.name, formattedValue, bar, arrow))
                }
            }
            print()
        }
    }

    /// A short ASCII bar indicating relative heat (60° = baseline, 95° = full)
    private func thermalBar(celsius: Double) -> String {
        let normalized = max(0, min(1, (celsius - 40) / 55))  // 40°=0, 95°=1
        let filled = Int(normalized * 8)
        let empty  = 8 - filled
        return "[" + String(repeating: "█", count: filled) + String(repeating: "░", count: empty) + "]"
    }
}

private extension SensorGroup {
    var displayName: String {
        switch self {
        case .cpuCore:    return "CPU Cores"
        case .gpu:        return "GPU"
        case .nand:       return "Storage"
        case .battery:    return "Battery"
        case .enclosure:  return "Enclosure"
        case .vrm:        return "VRM"
        case .wireless:   return "Wireless"
        case .power:      return "Power"
        case .clockSpeed: return "Clock Speeds"
        case .other:      return "Other Sensors"
        }
    }
}
