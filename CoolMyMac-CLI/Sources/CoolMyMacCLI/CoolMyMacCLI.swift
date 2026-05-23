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
        Connects to the CoolMyMac daemon via XPC. Reading sensors and fans is always 
        allowed for any user. Modifying fan profiles requires root (sudo) UNLESS you 
        have explicitly enabled 'Allow Unprivileged CLI' in the CoolMyMac App Preferences.
        """,
        subcommands: [
            TempsCommand.self,
            FansCommand.self,
            ProfileCommand.self,
            ResetCommand.self,
        ]
    )
}
