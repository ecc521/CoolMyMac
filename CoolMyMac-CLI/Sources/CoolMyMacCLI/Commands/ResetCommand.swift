// ResetCommand.swift
// `coolmymac reset` — resets all fans to Apple's automatic control.

import ArgumentParser
import Foundation

struct ResetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reset",
        abstract: "Reset all fans to Apple's automatic control (sets profile to Auto)"
    )

    @Flag(name: .shortAndLong, help: "Skip confirmation prompt")
    var yes: Bool = false

    mutating func run() async throws {
        if !yes {
            print("This will hand all fan control back to Apple's thermal management.")
            print("Proceed? [y/N] ", terminator: "")
            let input = readLine()?.lowercased() ?? ""
            guard input == "y" || input == "yes" else {
                print("Aborted.")
                return
            }
        }

        let result = await CLIContext.resetAllFans()

        switch result {
        case .failure(let err):
            fputs(err.message + "\n", stderr)
            throw ExitCode.failure

        case .success:
            print("✅ All fans reset to Auto (Apple thermal management)")
        }
    }
}
