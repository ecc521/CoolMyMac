# CoolMyMac Architecture & Implementation Plan

This document outlines the architecture and approach for building CoolMyMac, a modern alternative to SMC Fan Control.

## Architecture & Project Structure

To interact with the SMC (System Management Controller) to control fan speeds, root privileges are required for writing values. We will use a multi-target architecture within a single **Xcode Workspace** (`CoolMyMac.xcworkspace`), targeting **macOS 15.0 (Sequoia)** as the minimum deployment target (lower versions supported opportunistically).

1. **SMCKit (Shared Swift Package)**: The core logic. It will define an internal abstraction protocol (`SMCProvider` defining `readTemperature()`, `readFanSpeed(fanIndex:)`, `setFanSpeed(fanIndex:rpm:)`). It will contain the Intel (`AppleSMC`) backend; the Apple Silicon (`IOHIDEventSystem`) backend is stubbed and deferred to Phase 4. **This package also hosts the shared `@objc protocol` for XPC (`CoolMyMacXPCProtocol`)** so the Daemon, App, and CLI all agree on the IPC contract. Additionally, it defines the `FanProfile` and `FanCurve` model types used across all targets. *Note: The XPC protocol must use only ObjC-compatible types (no Swift structs/enums with associated values). Use callback-style methods with `withReply: @escaping (Data?, Error?) -> Void`.*
2. **CoolMyMac Daemon (LaunchDaemon)**: A system-level background process running as `root`. It implements the shared XPC protocol and listens for connections (`NSXPCListener`). It runs a thermal polling loop (reading SMC sensors, aggregating them, and adjusting fan speeds per the active profile). It must use `os.Logger` for all diagnostics. *Note: This is a system LaunchDaemon, not a sandboxed XPC Service.*
3. **CoolMyMac CLI**: A Swift-based command-line tool built with `swift-argument-parser`. The CLI prioritizes connecting to the Daemon via XPC. If the daemon is unreachable, it prints an explicit message and falls back to direct SMC access. If that also fails due to permissions, it exits with an actionable error.
4. **CoolMyMac UI (App)**: A native SwiftUI `MenuBarExtra` application. It embeds the LaunchDaemon in its bundle (`Contents/Library/LaunchDaemons/`) and installs it using `SMAppService.daemon(plistName:)`.

## Fan Profiles & Presets

Fan speed is controlled via a **piecewise linear thermal curve**: an ordered array of `(temperature °C, target RPM)` breakpoints. The Daemon interpolates between breakpoints and applies a **smoothing window** (default: 5-second rolling average) to prevent RPM hunting.

### Built-in Presets

| Preset | Description |
|---|---|
| **Auto** | No override — Apple's default thermal management is active. CoolMyMac does not touch fan speeds. |
| **Balanced** *(default)* | Matches Apple's minimum RPM floor; raises the ceiling more aggressively for developer workloads. |
| **Performance** | Higher minimum RPM floor; fans ramp up earlier and hit max around 85°C. |
| **Max** | Fans always run at maximum RPM. |

Custom profiles are stored as JSON in `~/Library/Application Support/CoolMyMac/profiles/`.

### Temperature Aggregation

The daemon reads a configurable set of sensor groups (default: **CPU cores + GPU**) and drives the fan curve from the **maximum** value across all sensors in the active set. This ensures no individual hot core is ignored.

| Setting | Default | Options |
|---|---|---|
| `sources` | `[CPU_CORES, GPU]` | Any combination of CPU_CORES, GPU, NAND |
| `aggregation` | `MAX` | `MAX` or `AVERAGE` |
| `smoothing_window` | `5s` | Configurable per-profile |

Fan speed control is expressed as **minimum RPM** (raw RPM values, not percentages). Each fan can be configured independently (e.g., left fan vs. right fan on MacBook Pros).

## UI Design Spec

### Visual Language
- **Appearance**: Follows system light/dark mode. Accent color: **blue** (system blue works well; evokes cooling).
- **Typography**: SF Pro (system default) throughout. No custom fonts.
- **Iconography**: SF Symbols throughout.
- **Materials**: Native macOS materials (`regularMaterial` for popover, `thickMaterial` for sidebars/headers in the Preferences window).

### Menu Bar Icon
A custom icon (fan or snowflake-adjacent) rendered as a template image. Behavior is user-configurable:

| Setting | Options |
|---|---|
| **Display mode** | Icon only / Icon + CPU temp / Icon + Fan RPM |
| **Dynamic color** | Enabled (default) / Disabled |

When **dynamic color** is enabled, the icon uses a **continuous color gradient** interpolated from the hottest active sensor reading:
- `≤ 60°C` — green
- `60–90°C` — smooth gradient green → yellow → orange → red
- `≥ 90°C` — red (fully saturated)

Implemented as a `Color(hue:)` interpolation: hue shifts from `0.33` (green) to `0.0` (red) proportionally within the 60–90°C range.

### Popover (Primary UI)
Opens when the user clicks the menu bar icon. ~320px wide, native popover style with frosted glass material. No title bar.

**Layout (top → bottom):**
1. **Header row** — App name + current active preset badge + a gear icon (→ opens Preferences)
2. **Sensor readings** — Two stat tiles side by side: CPU Temp and GPU Temp (large value, small label)
3. **Fan RPMs** — One row per physical fan (e.g., "Left Fan — 2,400 RPM", "Right Fan — 2,200 RPM"). Hidden if only one fan.
4. **Preset selector** — Segmented-style picker or pill buttons:
   - Built-in: `Auto` · `Balanced` · `Performance` · `Max`
   - Custom slots: Up to 3 named custom presets appear **only if at least one is defined** (e.g., `"Dev Mode"`)
   - Active preset highlighted in blue
5. **Footer** — Small text: daemon status indicator (green dot = running, red = not installed)
6. **Warning bar** (conditional) — If the user previously denied the daemon installation auth prompt, a yellow/amber dismissible banner appears at the bottom of the popover: *"Daemon not installed — fan control is inactive. [Grant Permission]"* Tapping it re-triggers `SMAppService.requestAuthorization()`.

### Preferences Window
A full `NSWindow` (not a sheet or panel) that feels like a real app. Opens from the gear icon in the popover or from the app menu.

**Sidebar navigation** (macOS Settings-style):
| Section | Contents |
|---|---|
| **General** | Launch at login, menu bar display mode, dynamic icon toggle |
| **Profiles** | List of all profiles (built-in + custom); select/edit/delete; create new |
| **Profile Editor** | (Phase 3) Edit name, sensor sources, aggregation, smoothing; view the temp/RPM curve (read-only). Phase 4 adds drag-to-edit curve. |
| **Sensors** | Live readout of all available SMC sensors for power users |
| **About** | Version, credits, daemon version |

## Code Signing & Entitlements (Crucial Prerequisite)

For `SMAppService.daemon(plistName:)` to successfully install a LaunchDaemon, strict code signing is required:
- Both the App and Daemon must be signed with a valid **Developer ID** certificate (already provisioned).
- The Daemon's embedded `launchd` plist `Label` must exactly match its bundle identifier. It requires a `MachServices` dictionary entry corresponding to its XPC service name.
- If the Daemon requires specific capabilities to access `IOKit` directly, required entitlements will be researched during Phase 1.

## UX & Graceful Degradation

- **Auto Mode / Daemon Not Running**: If no profile override is active, or the daemon cannot be reached, Apple's default thermal management remains in control — fans are never left stuck at a bad speed.
- **Admin Prompt Denied**: If the user denies the `SMAppService` installation auth prompt, the UI gracefully falls back to a "Read-Only" mode (display temps/RPM, no control).
- **Unsupported Hardware / VMs**: If `IOKit` cannot find SMC keys, `SMCKit` surfaces clear domain errors rather than crashing, and the UI displays "N/A" for sensors.

## Development Sequence

**Phase 1 — Workspace & Core SMCKit:**
> Initialize `CoolMyMac.xcworkspace`. Create local Swift Package `SMCKit` targeting macOS 15.0. Define the shared `@objc` XPC protocol (`CoolMyMacXPCProtocol`). Define `SMCProvider` protocol, implement the Intel `AppleSMC` backend. Define `FanProfile` and `FanCurve` model types. Stub the Apple Silicon backend (disabled).

**Phase 2 — CLI Integration:**
> Create `CoolMyMac-CLI` command-line tool in the workspace using `swift-argument-parser` and `SMCKit`. Prioritize XPC connection to daemon; degrade gracefully to direct SMC access with explicit messaging.

**Phase 3 — LaunchDaemon & UI:**
> Create `CoolMyMac-Daemon` target: `NSXPCListener`, thermal polling loop (with smoothing), profile management XPC methods. Create `CoolMyMac-App` SwiftUI `MenuBarExtra`: embeds daemon, `SMAppService` installation UX, preset picker (Auto/Balanced/Performance/Max), graceful degradation. Configure Developer ID code signing.

**Phase 4 — Apple Silicon & Custom Curves (deferred ~10 days):**
> Implement `IOHIDEventSystem` Apple Silicon backend. Add custom curve editor UI (temp/RPM graph with draggable breakpoints). Per-fan independent configuration.

## Verification Plan

1. **SMC Core Validation**: Run `CoolMyMac-CLI read temps` — verify temperature readings (20–105°C) and fan RPM readings (0–6000 RPM).
2. **Daemon Installation Check**: Trigger `SMAppService` installation and verify daemon is running via `sfltool dumpbtm`.
3. **Profile Switching**: Switch between Balanced and Performance presets and verify fan RPM changes accordingly within a few seconds (smoothing window).
4. **End-to-End Fan Control**: Confirm the UI sends the XPC message and the Daemon successfully writes the target RPM via `IOKit`.
