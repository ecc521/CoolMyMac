// main.swift
// CoolMyMac-Daemon entry point.
// Starts an NSXPCListener and runs the run loop indefinitely.

import Foundation
import SMCKit
import os.log

let logger = Logger(subsystem: "com.coolmymac.daemon", category: "main")

// Ensure we're running as root (required for SMC writes)
/*
guard getuid() == 0 else {
    logger.critical("Daemon must run as root. Exiting.")
    fputs("CoolMyMac-Daemon must run as root.\n", stderr)
    exit(1)
}
*/

func resetFansAndExit(_ sig: Int32) {
    logger.critical("Daemon received signal \(sig). Resetting fans to Apple Auto before exiting.")
    if let smc = try? SMCController() {
        try? smc.resetAllFans()
    }
    exit(sig)
}

signal(SIGINT, resetFansAndExit)
signal(SIGTERM, resetFansAndExit)
signal(SIGHUP, resetFansAndExit)
signal(SIGABRT, resetFansAndExit)

logger.info("CoolMyMac-Daemon starting (version \(daemonVersionString, privacy: .public))")

// Start the XPC listener
let server = DaemonXPCServer()
server.start()

// Block forever — launchd will manage the lifecycle
dispatchMain()
