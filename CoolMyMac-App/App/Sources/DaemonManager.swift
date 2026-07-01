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

    private let service = SMAppService.daemon(plistName: "com.coolmymac.app.daemon.plist")

    // MARK: - Status

    func currentStatus() -> DaemonInstallStatus {
        let s = service.status
        logger.debug("SMAppService status: \(String(describing: s))")
        switch s {
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
            // SMAppService status may not update synchronously after register().
            // Poll until it settles (up to ~3 seconds) before returning.
            let finalStatus = try await waitForStatus(timeout: 3.0)
            logger.info("Daemon registered. Final status: \(String(describing: finalStatus))")
            if finalStatus == .requiresApproval {
                openSystemSettingsForApproval()
            }
        } catch {
            logger.error("Failed to register daemon: \(error.localizedDescription, privacy: .public)")
            // register() may throw on macOS 26+ when approval is required rather than
            // transitioning status to .requiresApproval. Check the post-throw status
            // and open System Settings if it's waiting for user approval.
            // macOS 26 also does not reliably deliver the BTM notification.
            if service.status == .requiresApproval {
                openSystemSettingsForApproval()
            }
            throw error
        }
    }

    // Polls service.status until it is no longer .notRegistered, or until timeout.
    private func waitForStatus(timeout: Double) async throws -> SMAppService.Status {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let s = service.status
            if s != .notRegistered {
                return s
            }
            try await Task.sleep(nanoseconds: 300_000_000) // 0.3s
        }
        return service.status
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
        logger.info("Repair: unregistering daemon (current status: \(String(describing: self.service.status)))")
        try? await uninstallDaemon()
        // Give BTM time to fully clear the old registration before re-registering.
        // On dev builds without a version bump, re-registration may require user
        // re-approval in System Settings (macOS 26+ LWCR update requirement).
        try await Task.sleep(nanoseconds: 1_500_000_000)
        logger.info("Repair: re-registering daemon")
        do {
            try await installDaemon()
            logger.info("Repair: daemon re-registered successfully")
        } catch {
            logger.error("Repair: re-registration failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
}
