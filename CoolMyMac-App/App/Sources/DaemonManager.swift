// DaemonManager.swift
// Manages daemon installation and status via SMAppService.

import Foundation
import AppKit
import ServiceManagement
import SMCKit
import os.log

private let logger = Logger(subsystem: "com.coolmymac.app", category: "DaemonManager")

@MainActor
final class DaemonManager: ObservableObject {

    static let shared = DaemonManager()

    private let service = SMAppService.daemon(plistName: "com.coolmymac.daemon.plist")

    // MARK: - Status

    func currentStatus() -> DaemonInstallStatus {
        switch service.status {
        case .enabled:               return .installed
        case .notRegistered:         return .notInstalled
        case .requiresApproval:      return .requiresApproval
        case .notFound:              return .notInstalled
        @unknown default:            return .unknown
        }
    }

    // MARK: - Install

    func installDaemon() async throws {
        do {
            try service.register()
            logger.info("Daemon registered via SMAppService")
        } catch {
            logger.error("Failed to register daemon: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    // MARK: - Uninstall

    func uninstallDaemon() async throws {
        do {
            try await service.unregister()
            logger.info("Daemon unregistered")
        } catch {
            logger.error("Failed to unregister daemon: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    // MARK: - Open System Settings (for re-grant after denial)

    func openSystemSettingsForApproval() {
        // Opens Privacy & Security > Login Items & Extensions where the user can grant access
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Repair

    func repairDaemon() async throws {
        // Unregister and re-register
        try? await uninstallDaemon()
        try await Task.sleep(nanoseconds: 500_000_000)
        try await installDaemon()
        logger.info("Daemon repair attempted")
    }
}
