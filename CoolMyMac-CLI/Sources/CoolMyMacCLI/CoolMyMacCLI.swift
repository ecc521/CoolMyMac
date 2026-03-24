// CoolMyMacCLI.swift
// Root command and entry point for the CoolMyMac CLI.

import ArgumentParser
import Foundation

@main
struct CoolMyMacCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "coolmymac",
        abstract: "CoolMyMac fan control CLI",
        discussion: """
        Connects to the CoolMyMac daemon via XPC to read sensors and control fan speeds
        without requiring sudo. If the daemon is unreachable, falls back to direct SMC
        access (requires root privileges).
        """,
        subcommands: [
            TempsCommand.self,
            FansCommand.self,
            ProfileCommand.self,
            ResetCommand.self,
        ],
        defaultSubcommand: TempsCommand.self
    )
}
