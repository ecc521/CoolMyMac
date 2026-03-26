# ChillMac (formerly CoolMyMac)

A modern, lightweight fan control utility for macOS 15.0+ with a beautiful Menu Bar interface.

## Features
- **Dynamic Menu Bar Icon**: The icon automatically shifts from blue to red as your CPU/GPU gets hotter.
- **Built-in Presets**:
  - `Quiet`: Leaves Apple's default thermal management fully in control.
  - `Balanced`: Matches Apple's minimum RPM floor but raises the ceiling more aggressively for developer workloads.
  - `Performance`: Higher minimum RPMs and an aggressive ramp-up to max speed around 85°C.
  - `Max`: Forces all fans to run at maximum speed instantly.
- **Multi-Target Architecture**:
  - `ChillMac`: A SwiftUI App containing the MenuBarExtra and robust Preferences window.
  - `ChillMac-Daemon`: A LaunchDaemon running as `root` (with an XPC listener) needed to write speeds to the SMC.
  - `ChillMacCLI`: A powerful command-line interface for scripting profile changes (`chillmac temps`, `chillmac fans`, `chillmac set max`).
- **Graceful Fallback**: If you choose not to install the daemon via `SMAppService`, you can still use the app to monitor live CPU/GPU temperatures and active fan RPMs in real-time natively!

## Requirements
- macOS 15.0 (Sequoia) or newer
- Apple Developer ID (required to locally code-sign the LaunchDaemon for `SMAppService`)

## How to Build & Run

### 1. Generating the Xcode Project
The `.xcodeproj` is generated using `xcodegen`. If you modify the project structure, regenerate it:
```bash
brew install xcodegen
cd CoolMyMac-App
xcodegen generate
```

### 2. Code Signing (Required for Daemon)
Because macOS requires LaunchDaemons installed via `SMAppService` to be signed by the same Team ID as the host app, you **must** configure code signing manually before building:
1. Open `CoolMyMac-App/CoolMyMac.xcodeproj` in Xcode.
2. Select the `CoolMyMac` target -> **Signing & Capabilities**.
3. Select your Personal Team or Apple Developer ID.
4. Repeat this exact process for the `CoolMyMac-Daemon` target.

### 3. Running the App
Once signed, you can run the app directly from Xcode:
1. Select the `CoolMyMac` scheme in the top bar.
2. Hit **Cmd + R** (Run).
3. The app will appear in your Mac's Menu Bar. Click the gear icon to open Preferences, and navigate to **General > Install Daemon** to activate fan control.

### 4. Building the CLI
The CLI is built using the Swift Package Manager.
```bash
cd CoolMyMac-CLI
swift build -c release
# The binary will be output to: .build/release/CoolMyMacCLI
```
