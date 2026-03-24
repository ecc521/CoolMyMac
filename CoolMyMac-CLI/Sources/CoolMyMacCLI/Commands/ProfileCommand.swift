// ProfileCommand.swift
// `coolmymac profile` — get or set the active fan profile.

import ArgumentParser
import Foundation
import SMCKit

struct ProfileCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "profile",
        abstract: "Get or set the active fan profile",
        subcommands: [
            GetProfileCommand.self,
            SetProfileCommand.self,
            ListProfilesCommand.self,
        ],
        defaultSubcommand: GetProfileCommand.self
    )
}

// MARK: - Get

struct GetProfileCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "get",
        abstract: "Show the currently active profile"
    )

    @Flag(name: .long, help: "Output raw JSON")
    var json: Bool = false

    mutating func run() async throws {
        let result = await CLIContext.activeProfile()

        switch result {
        case .failure(let err):
            fputs(err.message + "\n", stderr)
            throw ExitCode.failure

        case .success(let profile):
            if json {
                let data = try JSONEncoder().encode(profile)
                print(String(decoding: data, as: UTF8.self))
                return
            }

            print("\nActive Profile: \(profile.displayName)\(profile.isBuiltIn ? " (built-in)" : "")")

            let settings = profile.settings
            print("  Sensor sources:  \(settings.sources.map(\.rawValue).joined(separator: ", "))")
            print("  Aggregation:     \(settings.aggregation.rawValue)")
            print("  Smoothing:       \(settings.smoothingWindowSeconds)s")

            if profile.curve.points.isEmpty {
                print("  Curve:           None (Apple manages fans)")
            } else {
                print("  Curve:           \(profile.curve.points.count) breakpoints")
                for point in profile.curve.points {
                    print(String(format: "    %5.1f°C → %5d RPM", point.celsius, point.rpm))
                }
            }
            print()
        }
    }
}

// MARK: - Set

struct SetProfileCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set",
        abstract: "Set the active fan profile",
        discussion: "Built-in profiles: auto, balanced, performance, max"
    )

    @Argument(help: "Profile name to activate (e.g. 'balanced', 'performance', 'my-profile')")
    var name: String

    mutating func run() async throws {
        let result = await CLIContext.setActiveProfile(name)

        switch result {
        case .failure(let err):
            fputs(err.message + "\n", stderr)
            throw ExitCode.failure

        case .success:
            print("✅ Profile set to '\(name)'")
        }
    }
}

// MARK: - List

struct ListProfilesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all available profiles"
    )

    mutating func run() async throws {
        let result = await CLIContext.listProfiles()

        switch result {
        case .failure(let err):
            fputs(err.message + "\n", stderr)
            throw ExitCode.failure

        case .success(let names):
            let builtIns = Set(FanProfile.allBuiltIn.map(\.id))
            print("\nAvailable Profiles")
            print(String(repeating: "─", count: 30))
            for name in names {
                let tag = builtIns.contains(name) ? " (built-in)" : " (custom)"
                print("  • \(name)\(tag)")
            }
            print()
        }
    }
}
