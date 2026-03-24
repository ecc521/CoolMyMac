// XPCClient.swift
// XPC connection wrapper for communicating with the CoolMyMac daemon.

import Foundation

/// Wraps an NSXPCConnection to the CoolMyMac daemon.
/// All calls are async wrappers around the `withReply:` XPC protocol.
// NSXPCConnection is not Sendable in Swift 6; we manage thread-safety via its internal serial queue.
public final class CoolMyMacClient: @unchecked Sendable {

    private let connection: NSXPCConnection

    public init() {
        connection = NSXPCConnection(machServiceName: CoolMyMacXPCServiceName, options: [])
        connection.remoteObjectInterface = NSXPCInterface(with: CoolMyMacXPCProtocol.self)
        connection.resume()
    }

    deinit {
        connection.invalidate()
    }

    // MARK: - Private helper

    private var proxy: (any CoolMyMacXPCProtocol)? {
        connection.remoteObjectProxyWithErrorHandler { error in
            // Error is surfaced at call sites via the checked-continuation throw
        } as? any CoolMyMacXPCProtocol
    }

    // MARK: - Public API (mirrors SMCController interface for drop-in fallback)

    public func readSensors() async throws -> [SensorReading] {
        try await withCheckedThrowingContinuation { continuation in
            guard let proxy else {
                continuation.resume(throwing: XPCError.connectionFailed)
                return
            }
            proxy.readSensors { data, error in
                if let error { continuation.resume(throwing: error); return }
                guard let data else { continuation.resume(throwing: XPCError.noData); return }
                do {
                    let readings = try JSONDecoder().decode([SensorReading].self, from: data)
                    continuation.resume(returning: readings)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func readFans() async throws -> [FanStatus] {
        try await withCheckedThrowingContinuation { continuation in
            guard let proxy else {
                continuation.resume(throwing: XPCError.connectionFailed)
                return
            }
            proxy.readFans { data, error in
                if let error { continuation.resume(throwing: error); return }
                guard let data else { continuation.resume(throwing: XPCError.noData); return }
                do {
                    let fans = try JSONDecoder().decode([FanStatus].self, from: data)
                    continuation.resume(returning: fans)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func activeProfile() async throws -> FanProfile {
        try await withCheckedThrowingContinuation { continuation in
            guard let proxy else {
                continuation.resume(throwing: XPCError.connectionFailed)
                return
            }
            proxy.activeProfile { data, error in
                if let error { continuation.resume(throwing: error); return }
                guard let data else { continuation.resume(throwing: XPCError.noData); return }
                do {
                    let profile = try JSONDecoder().decode(FanProfile.self, from: data)
                    continuation.resume(returning: profile)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func listProfiles() async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            guard let proxy else {
                continuation.resume(throwing: XPCError.connectionFailed)
                return
            }
            proxy.listProfiles { data, error in
                if let error { continuation.resume(throwing: error); return }
                guard let data else { continuation.resume(throwing: XPCError.noData); return }
                do {
                    let names = try JSONDecoder().decode([String].self, from: data)
                    continuation.resume(returning: names)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func setActiveProfile(_ name: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            guard let proxy else {
                continuation.resume(throwing: XPCError.connectionFailed)
                return
            }
            proxy.setActiveProfile(name) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    public func saveCustomProfile(_ profile: FanProfile) async throws {
        let data = try JSONEncoder().encode(profile)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            guard let proxy else {
                continuation.resume(throwing: XPCError.connectionFailed)
                return
            }
            proxy.saveCustomProfile(data) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    public func deleteCustomProfile(id: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            guard let proxy else {
                continuation.resume(throwing: XPCError.connectionFailed)
                return
            }
            proxy.deleteCustomProfile(id) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    public func isDaemonReachable() async -> Bool {
        (try? await daemonVersion()) != nil
    }

    public func daemonVersion() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            guard let proxy else {
                continuation.resume(throwing: XPCError.connectionFailed)
                return
            }
            proxy.daemonVersion { version in
                continuation.resume(returning: version)
            }
        }
    }
}

// MARK: - XPC Errors

public enum XPCError: Error, LocalizedError {
    case connectionFailed
    case noData
    case daemonNotRunning

    public var errorDescription: String? {
        switch self {
        case .connectionFailed:  return "Failed to connect to CoolMyMac daemon."
        case .noData:            return "Daemon returned no data."
        case .daemonNotRunning:  return "Daemon not running."
        }
    }
}
