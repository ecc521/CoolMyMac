// FansCommand.swift
// `coolmymac fans` — lists all fan status.

import ArgumentParser
import Foundation
import SMCKit

struct FansCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "fans",
        abstract: "Display current fan speeds and status"
    )

    @Flag(name: .long, help: "Output raw JSON")
    var json: Bool = false

    mutating func run() async throws {
        let result = await CLIContext.readFans()

        switch result {
        case .failure(let err):
            fputs(err.message + "\n", stderr)
            throw ExitCode.failure

        case .success(let fans):
            if json {
                let data = try JSONEncoder().encode(fans)
                print(String(decoding: data, as: UTF8.self))
                return
            }

            if fans.isEmpty {
                print("No fans detected.")
                return
            }

            print("\nFan Status")
            print(String(repeating: "─", count: 40))
            for fan in fans {
                let managedLabel = fan.isManaged ? " [managed by CoolMyMac]" : " [Apple auto]"
                let rpmBar = rpmBar(current: fan.currentRPM, maxRPM: fan.maxRPM)
                print(String(format: "\n  %@%@", fan.name, managedLabel))
                print(String(format: "  Current: %5d RPM  %@", fan.currentRPM, rpmBar))
                print(String(format: "  Min:     %5d RPM", fan.minRPM))
                print(String(format: "  Max:     %5d RPM", fan.maxRPM))
            }
            print()
        }
    }

    private func rpmBar(current: Int, maxRPM: Int) -> String {
        guard maxRPM > 0 else { return "[░░░░░░░░]" }
        let normalized = max(0.0, min(1.0, Double(current) / Double(maxRPM)))
        let filled = Int(normalized * 8)
        let empty  = 8 - filled
        return "[" + String(repeating: "█", count: filled) + String(repeating: "░", count: empty) + "]"
    }
}
