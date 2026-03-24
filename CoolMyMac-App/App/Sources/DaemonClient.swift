// DaemonClient.swift
// XPC client for the App — mirrors the CLI's XPCClient.

import Foundation
import SMCKit

final class DaemonClient: @unchecked Sendable {

    private let connection: NSXPCConnection

    init() {
        connection = NSXPCConnection(machServiceName: CoolMyMacXPCServiceName, options: [])
        connection.remoteObjectInterface = NSXPCInterface(with: CoolMyMacXPCProtocol.self)
        connection.resume()
    }

    deinit { connection.invalidate() }

    private var proxy: (any CoolMyMacXPCProtocol)? {
        connection.remoteObjectProxyWithErrorHandler { _ in } as? any CoolMyMacXPCProtocol
    }

    func readSensors() async throws -> [SensorReading] {
        try await xpcCall { proxy, reply in proxy.readSensors(withReply: reply) }
    }

    func readFans() async throws -> [FanStatus] {
        try await xpcCall { proxy, reply in proxy.readFans(withReply: reply) }
    }

    func activeProfile() async throws -> FanProfile {
        try await xpcCall { proxy, reply in proxy.activeProfile(withReply: reply) }
    }

    func listProfiles() async throws -> [String] {
        try await xpcCall { proxy, reply in proxy.listProfiles(withReply: reply) }
    }

    func setActiveProfile(_ name: String) async throws {
        guard let proxy else { throw DaemonClientError.notConnected }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            proxy.setActiveProfile(name) { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            }
        }
    }

    func saveCustomProfile(_ profile: FanProfile) async throws {
        guard let proxy else { throw DaemonClientError.notConnected }
        let data = try JSONEncoder().encode(profile)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            proxy.saveCustomProfile(data) { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            }
        }
    }

    func deleteCustomProfile(id: String) async throws {
        guard let proxy else { throw DaemonClientError.notConnected }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            proxy.deleteCustomProfile(id) { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            }
        }
    }

    func isDaemonReachable() async -> Bool {
        (try? await readSensors()) != nil
    }

    // MARK: - Generic helper

    private func xpcCall<T: Decodable & Sendable>(
        _ call: @escaping (any CoolMyMacXPCProtocol, @escaping (Data?, Error?) -> Void) -> Void
    ) async throws -> T {
        guard let proxy else { throw DaemonClientError.notConnected }
        return try await withCheckedThrowingContinuation { cont in
            call(proxy) { data, error in
                if let error { cont.resume(throwing: error); return }
                guard let data else { cont.resume(throwing: DaemonClientError.noData); return }
                do { cont.resume(returning: try JSONDecoder().decode(T.self, from: data)) }
                catch { cont.resume(throwing: error) }
            }
        }
    }
}

enum DaemonClientError: Error, LocalizedError {
    case notConnected, noData
    var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to daemon."
        case .noData:       return "No data returned from daemon."
        }
    }
}
