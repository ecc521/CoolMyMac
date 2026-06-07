// ResetCommand.swift
// `coolmymac reset` — resets all fans to Apple's automatic control.

import ArgumentParser
import Foundation

struct ResetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reset",
        abstract: "Reset all fans to Apple's automatic control (sets profile to System)"
    )

    mutating func run() async throws {
        let result = await CLIContext.resetAllFans()

        switch result {
        case .failure(let err):
            fputs(err.message + "\n", stderr)
            throw ExitCode.failure

        case .success:
            print("✅ All fans reset to System (Apple thermal management)")
        }
    }
}
