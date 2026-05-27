// CLIContext.swift
// Shared entry point for CLI commands.
// Tries XPC first; falls back to direct SMC access with explicit messaging.

import Foundation
import SMCKit

/// Resolves the best available data source: XPC (daemon) or direct SMC.
/// CLI commands use this instead of touching XPCClient / SMCController directly.
enum CLIContext {

    // MARK: - Sensor & Fan reads (read-only, no root needed via XPC)

    static func readSensors(all: Bool = false) async -> Result<[SensorReading], CLIContextError> {
        let xpc = CoolMyMacClient()
        do {
            let readings = try await (all ? xpc.readAllSensors() : xpc.readSensors())
            return .success(readings)
        } catch {
            // Daemon unreachable — fall back to direct SMC
            printDaemonFallbackMessage()
            do {
                let controller = try SMCController()
                let readings = try controller.readTemperatures(for: all ? nil : [.cpuCore, .gpu])
                return .success(readings)
            } catch let smcError as SMCError {
                return .failure(.smcError(smcError))
            } catch {
                return .failure(.unknown(error))
            }
        }
    }

    static func readFans() async -> Result<[FanStatus], CLIContextError> {
        let xpc = CoolMyMacClient()
        do {
            let fans = try await xpc.readFans()
            return .success(fans)
        } catch {
            printDaemonFallbackMessage()
            do {
                let controller = try SMCController()
                let fans = try controller.readAllFans()
                return .success(fans)
            } catch let smcError as SMCError {
                return .failure(.smcError(smcError))
            } catch {
                return .failure(.unknown(error))
            }
        }
    }

    // MARK: - Profile management (requires daemon — no direct-SMC fallback)

    static func activeProfile() async -> Result<FanProfile, CLIContextError> {
        let xpc = CoolMyMacClient()
        do {
            let profile = try await xpc.activeProfile()
            return .success(profile)
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain {
                return .failure(.daemonRequired("Profile management requires the daemon to be running."))
            }
            return .failure(.profileError(error.localizedDescription))
        }
    }

    static func listProfiles() async -> Result<[String], CLIContextError> {
        let xpc = CoolMyMacClient()
        do {
            let names = try await xpc.listProfiles()
            return .success(names)
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain {
                return .failure(.daemonRequired("Profile management requires the daemon to be running."))
            }
            return .failure(.profileError(error.localizedDescription))
        }
    }

    static func setActiveProfile(_ name: String) async -> Result<Void, CLIContextError> {
        let xpc = CoolMyMacClient()
        do {
            try await xpc.setActiveProfile(name)
            return .success(())
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain {
                return .failure(.daemonRequired("Setting a profile requires the daemon to be running."))
            }
            return .failure(.profileError(error.localizedDescription))
        }
    }

    // MARK: - Reset (requires root if direct)

    static func resetAllFans() async -> Result<Void, CLIContextError> {
        let xpc = CoolMyMacClient()
        do {
            // Reset = set System profile
            try await xpc.setActiveProfile("system")
            return .success(())
        } catch {
            printDaemonFallbackMessage()
            do {
                let controller = try SMCController()
                try controller.resetAllFans()
                return .success(())
            } catch let smcError as SMCError where smcError == .permissionDenied {
                return .failure(.permissionDenied)
            } catch let smcError as SMCError {
                return .failure(.smcError(smcError))
            } catch {
                return .failure(.unknown(error))
            }
        }
    }

    // MARK: - Private

    private static func printDaemonFallbackMessage() {
        fputs("⚠️  Daemon not running. Attempting direct SMC access (requires sudo)...\n", stderr)
    }
}

// MARK: - CLIContextError

enum CLIContextError: Error {
    case smcError(SMCError)
    case daemonRequired(String)
    case permissionDenied
    case profileError(String)
    case unknown(Error)

    var message: String {
        switch self {
        case .smcError(let e):
            return "SMC error: \(e.localizedDescription)"
        case .daemonRequired(let msg):
            return "❌ \(msg)\n   Install the CoolMyMac app to start the daemon."
        case .permissionDenied:
            return "❌ Permission denied. Run with sudo for direct SMC access:\n   sudo coolmymac reset"
        case .profileError(let msg):
            return "❌ \(msg)"
        case .unknown(let e):
            return "❌ Unexpected error: \(e.localizedDescription)"
        }
    }
}

extension SMCError: @retroactive Equatable {
    public static func == (lhs: SMCError, rhs: SMCError) -> Bool {
        lhs.errorDescription == rhs.errorDescription
    }
}
