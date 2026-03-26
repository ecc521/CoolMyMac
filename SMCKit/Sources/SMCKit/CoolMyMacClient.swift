// XPCClient.swift
// XPC connection wrapper for communicating with the CoolMyMac daemon.

import Foundation

/// Wraps an NSXPCConnection to the CoolMyMac daemon.
/// All calls are async wrappers around the `withReply:` XPC protocol.
// NSXPCConnection is not Sendable in Swift 6; we manage thread-safety via its internal serial queue.
public final class CoolMyMacClient: @unchecked Sendable {

    private var _connection: NSXPCConnection?
    private let lock = NSLock()

    private var connection: NSXPCConnection {
        lock.lock()
        defer { lock.unlock() }

        if let conn = _connection {
            return conn
        }

        let newConn = NSXPCConnection(machServiceName: CoolMyMacXPCServiceName, options: [])
        newConn.remoteObjectInterface = NSXPCInterface(with: CoolMyMacXPCProtocol.self)
        
        // If launchd kills the daemon or it crashes, safely nil out the reference
        // so the next XPC call automatically spawns a fresh connection pipeline.
        newConn.interruptionHandler = { [weak self] in
            self?.clearConnection()
        }
        newConn.invalidationHandler = { [weak self] in
            self?.clearConnection()
        }
        
        newConn.resume()
        _connection = newConn
        return newConn
    }

    public init() {}

    deinit {
        _connection?.invalidate()
    }

    private func clearConnection() {
        lock.lock()
        defer { lock.unlock() }
        _connection = nil
    }

    // MARK: - Private helper

    private func getProxy(errorHandler: @escaping (Error) -> Void) -> (any CoolMyMacXPCProtocol)? {
        connection.remoteObjectProxyWithErrorHandler { error in
            errorHandler(error)
        } as? any CoolMyMacXPCProtocol
    }

    // MARK: - Generic helper

    private func xpcCall<T: Decodable & Sendable>(
        _ call: @escaping (any CoolMyMacXPCProtocol, @escaping (Data?, Error?) -> Void) -> Void
    ) async throws -> T {
        return try await withCheckedThrowingContinuation { cont in
            var hasResumed = false
            guard let proxy = getProxy(errorHandler: { error in
                if !hasResumed { hasResumed = true; cont.resume(throwing: error) }
            }) else { return }
            
            call(proxy) { data, error in
                if hasResumed { return }
                hasResumed = true
                if let error { cont.resume(throwing: error); return }
                guard let data else { cont.resume(throwing: XPCError.noData); return }
                do { cont.resume(returning: try JSONDecoder().decode(T.self, from: data)) }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    // MARK: - Public API (mirrors SMCController interface for drop-in fallback)

    public func readSensors() async throws -> [SensorReading] {
        try await xpcCall { proxy, reply in proxy.readSensors(withReply: reply) }
    }

    public func readFans() async throws -> [FanStatus] {
        try await xpcCall { proxy, reply in proxy.readFans(withReply: reply) }
    }

    public func activeProfile() async throws -> FanProfile {
        try await xpcCall { proxy, reply in proxy.activeProfile(withReply: reply) }
    }

    public func listProfiles() async throws -> [String] {
        try await xpcCall { proxy, reply in proxy.listProfiles(withReply: reply) }
    }
    
    public func getCustomProfiles() async throws -> [FanProfile] {
        try await xpcCall { proxy, reply in proxy.getCustomProfiles(withReply: reply) }
    }

    public func setActiveProfile(_ name: String) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            var hasResumed = false
            guard let proxy = getProxy(errorHandler: { error in
                if !hasResumed { hasResumed = true; cont.resume(throwing: error) }
            }) else { return }
            
            proxy.setActiveProfile(name) { error in
                if !hasResumed { hasResumed = true; if let error { cont.resume(throwing: error) } else { cont.resume() } }
            }
        }
    }

    public func saveCustomProfile(_ profile: FanProfile) async throws {
        let data = try JSONEncoder().encode(profile)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            var hasResumed = false
            guard let proxy = getProxy(errorHandler: { error in
                if !hasResumed { hasResumed = true; cont.resume(throwing: error) }
            }) else { return }
            
            proxy.saveCustomProfile(data) { error in
                if !hasResumed { hasResumed = true; if let error { cont.resume(throwing: error) } else { cont.resume() } }
            }
        }
    }

    public func deleteCustomProfile(id: String) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            var hasResumed = false
            guard let proxy = getProxy(errorHandler: { error in
                if !hasResumed { hasResumed = true; cont.resume(throwing: error) }
            }) else { return }
            
            proxy.deleteCustomProfile(id) { error in
                if !hasResumed { hasResumed = true; if let error { cont.resume(throwing: error) } else { cont.resume() } }
            }
        }
    }

    public func isDaemonReachable() async -> Bool {
        (try? await daemonVersion()) != nil
    }

    public func setUpdateInterval(_ interval: Double) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            var hasResumed = false
            guard let proxy = getProxy(errorHandler: { error in
                if !hasResumed { hasResumed = true; cont.resume(throwing: error) }
            }) else { return }
            
            proxy.setUpdateInterval(interval) { error in
                if !hasResumed { hasResumed = true; if let error { cont.resume(throwing: error) } else { cont.resume() } }
            }
        }
    }

    public func getUpdateInterval() async throws -> Double {
        try await withCheckedThrowingContinuation { cont in
            var hasResumed = false
            guard let proxy = getProxy(errorHandler: { error in
                if !hasResumed { hasResumed = true; cont.resume(throwing: error) }
            }) else { return }
            
            proxy.getUpdateInterval { interval, error in
                if !hasResumed { hasResumed = true; if let error { cont.resume(throwing: error) } else { cont.resume(returning: interval) } }
            }
        }
    }

    public func setActiveSensors(_ groups: [SensorGroup]) async throws {
        let strings = groups.map(\.rawValue)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            var hasResumed = false
            guard let proxy = getProxy(errorHandler: { error in
                if !hasResumed { hasResumed = true; cont.resume(throwing: error) }
            }) else { return }
            
            proxy.setActiveSensors(strings) { error in
                if !hasResumed { hasResumed = true; if let error { cont.resume(throwing: error) } else { cont.resume() } }
            }
        }
    }

    public func getActiveSensors() async throws -> [SensorGroup] {
        let strings: [String] = try await withCheckedThrowingContinuation { cont in
            var hasResumed = false
            guard let proxy = getProxy(errorHandler: { error in
                if !hasResumed { hasResumed = true; cont.resume(throwing: error) }
            }) else { return }
            
            proxy.getActiveSensors { strings, error in
                if !hasResumed { hasResumed = true; if let error { cont.resume(throwing: error) } else { cont.resume(returning: strings) }
                }
            }
        }
        return strings.compactMap(SensorGroup.init(rawValue:))
    }

    public func daemonVersion() async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            var hasResumed = false
            guard let proxy = getProxy(errorHandler: { error in
                if !hasResumed { hasResumed = true; cont.resume(throwing: error) }
            }) else { return }
            
            proxy.daemonVersion { version in
                if !hasResumed { hasResumed = true; cont.resume(returning: version) }
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
