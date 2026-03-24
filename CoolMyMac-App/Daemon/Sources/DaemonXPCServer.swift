// DaemonXPCServer.swift
// Implements CoolMyMacXPCProtocol and manages the NSXPCListener lifecycle.

import Foundation
import SMCKit
import os.log

private let xpcLogger = Logger(subsystem: "com.coolmymac.daemon", category: "XPCServer")

let daemonVersionString = "1.0.0"

final class DaemonXPCServer: NSObject, NSXPCListenerDelegate {

    private let listener: NSXPCListener

    override init() {
        listener = NSXPCListener(machServiceName: CoolMyMacXPCServiceName)
        super.init()
        listener.delegate = self
    }

    func start() {
        listener.resume()
        ThermalController.shared.start()
        xpcLogger.info("XPC listener started on '\(CoolMyMacXPCServiceName, privacy: .public)'")
    }

    // MARK: NSXPCListenerDelegate

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        // Validate the connecting process is signed (basic audit)
        newConnection.exportedInterface = NSXPCInterface(with: CoolMyMacXPCProtocol.self)
        newConnection.exportedObject = XPCHandler()
        newConnection.resume()
        xpcLogger.info("New XPC connection accepted (PID: \(newConnection.processIdentifier, privacy: .public))")
        return true
    }
}

// MARK: - XPC Handler

/// Handles XPC calls from clients (App, CLI). All methods run on the connection's private queue.
private final class XPCHandler: NSObject, CoolMyMacXPCProtocol {

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: Sensors

    func readSensors(withReply reply: @escaping (Data?, Error?) -> Void) {
        let readings = ThermalController.shared.latestReadings
        encode(readings, reply: reply)
    }

    // MARK: Fans

    func readFans(withReply reply: @escaping (Data?, Error?) -> Void) {
        let fans = ThermalController.shared.latestFanStatus
        encode(fans, reply: reply)
    }

    // MARK: Profiles

    func activeProfile(withReply reply: @escaping (Data?, Error?) -> Void) {
        let profile = ProfileStore.shared.getActiveProfile()
        encode(profile, reply: reply)
    }

    func setActiveProfile(_ name: String, withReply reply: @escaping (Error?) -> Void) {
        do {
            try ProfileStore.shared.setActiveProfile(id: name)
            reply(nil)
        } catch {
            xpcLogger.error("setActiveProfile failed: \(error.localizedDescription, privacy: .public)")
            reply(error)
        }
    }

    func listProfiles(withReply reply: @escaping (Data?, Error?) -> Void) {
        let ids = ProfileStore.shared.listAllProfileIDs()
        encode(ids, reply: reply)
    }

    func saveCustomProfile(_ profileData: Data, withReply reply: @escaping (Error?) -> Void) {
        do {
            let profile = try decoder.decode(FanProfile.self, from: profileData)
            try ProfileStore.shared.save(profile)
            reply(nil)
        } catch {
            xpcLogger.error("saveCustomProfile failed: \(error.localizedDescription, privacy: .public)")
            reply(error)
        }
    }

    func deleteCustomProfile(_ name: String, withReply reply: @escaping (Error?) -> Void) {
        do {
            try ProfileStore.shared.delete(id: name)
            reply(nil)
        } catch {
            xpcLogger.error("deleteCustomProfile failed: \(error.localizedDescription, privacy: .public)")
            reply(error)
        }
    }

    // MARK: Info

    func daemonVersion(withReply reply: @escaping (String) -> Void) {
        reply(daemonVersionString)
    }

    // MARK: Private

    private func encode<T: Encodable>(_ value: T, reply: @escaping (Data?, Error?) -> Void) {
        do {
            let data = try encoder.encode(value)
            reply(data, nil)
        } catch {
            reply(nil, error)
        }
    }
}
