# CoolMyMac

![macOS 15.0+](https://img.shields.io/badge/macOS-15.0%2B-blue.svg)
![Swift 6](https://img.shields.io/badge/Swift-6-orange.svg)
![License](https://img.shields.io/badge/license-GPLv3-green.svg)

A modern, lightweight **macOS fan control** and **thermal management** utility for macOS 15.0+ with a beautiful Menu Bar interface. CoolMyMac provides complete control over your Mac's cooling system, deeply integrating with the macOS System Management Controller (SMC) to provide optimal cooling performance and thermal throttling prevention on both **Apple Silicon (M1/M2/M3/M4/M5)** and **Intel** Macs.

<p align="center">
  <img src="assets/screenshot.png" alt="CoolMyMac Menu Bar Interface" width="400">
</p>

## Table of Contents
- [Installation](#installation)
- [Features](#features)
- [Architecture](#architecture)
- [Build from Source](#build-from-source)
- [Contributing](#contributing)
- [License](#license)

## Installation

### Method 1: Homebrew (Recommended)
You can seamlessly install CoolMyMac and its accompanying CLI tool using Homebrew:
```bash
brew tap ecc521/coolmymac
brew install --cask coolmymac
```

### Method 2: DMG Download
Download the latest `CoolMyMac.dmg` from the [Releases](https://github.com/ecc521/CoolMyMac/releases) page. Open the DMG and simply drag `CoolMyMac.app` to your `/Applications` folder.

## Features
- **Dynamic Menu Bar Icon**: The icon automatically shifts from blue to red as your CPU/GPU gets hotter.
- **Apple Silicon & Intel SMC Support**: Native, low-level IOKit sensor readings for package power, CPU/GPU temps, and clock speeds.
- **Built-in Presets**:
  - `Quiet`: Leaves Apple's default thermal management fully in control.
  - `Balanced`: Matches Apple's minimum RPM floor but raises the ceiling more aggressively for developer workloads.
  - `Performance`: Higher minimum RPMs and an aggressive ramp-up to max speed around 85°C.
  - `Max`: Forces all fans to run at maximum speed instantly.
- **Command Line Interface (CLI)**: A powerful `coolmymac` tool for scripting profile changes (`coolmymac temps`, `coolmymac fans`, `coolmymac profile set max`).
- **Graceful Fallback**: If you choose not to install the daemon via `SMAppService`, you can still use the app to monitor live CPU/GPU temperatures and active fan RPMs in real-time natively!

## Architecture
- **App**: A SwiftUI MenuBarExtra application containing the Preferences window.
- **Daemon**: A secure `SMAppService` LaunchDaemon running as `root` (with an XPC listener) required to write speeds to the SMC safely.
- **CLI**: A standalone Swift package binary embedded in the App.

## Build from Source

If you wish to compile CoolMyMac yourself instead of using the pre-compiled DMG, follow these steps.

### 1. Code Signing (Required for Daemon)
Because macOS requires LaunchDaemons installed via `SMAppService` to be signed by the same Team ID as the host app, you **must** configure code signing manually before building:
1. Open `CoolMyMac-App/CoolMyMac.xcodeproj` in Xcode.
2. Select the `CoolMyMac` target -> **Signing & Capabilities**.
3. Select your Personal Team or Apple Developer ID.
4. Repeat this exact process for the `CoolMyMac-Daemon` target.

### 2. Running the App
Once signed, you can run the app directly from Xcode:
1. Select the `CoolMyMac` scheme in the top bar.
2. Hit **Cmd + R** (Run).
3. The app will appear in your Mac's Menu Bar. Click the gear icon to open Preferences, and navigate to **General > Install Daemon** to activate fan control.

### 3. Building the CLI
The CLI is built using the Swift Package Manager.
```bash
cd CoolMyMac-CLI
swift build -c release --arch arm64 --arch x86_64
# The universal binary will be output to: .build/apple/Products/Release/CoolMyMacCLI
```

## Contributing
We welcome contributions! Please see our [Contributing Guidelines](CONTRIBUTING.md) for more details on how to set up your environment and submit Pull Requests.

## License
This project is licensed under the [GNU General Public License v3.0](LICENSE).
