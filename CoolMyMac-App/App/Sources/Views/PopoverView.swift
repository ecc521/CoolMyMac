// PopoverView.swift
// The main popover shown when the user clicks the menu bar icon.
// ~320pt wide. No title bar. Native frosted glass material.

import SwiftUI
import SMCKit

struct PopoverView: View {

    var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {

            // MARK: 1. Header
            HStack {
                Image(systemName: "wind")
                    .foregroundStyle(.blue)
                    .font(.system(size: 14, weight: .semibold))
                Text("CoolMyMac")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                // Active preset badge
                Text(state.activeProfile.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.15), in: Capsule())
                    .foregroundStyle(.blue)
                // Gear → Preferences
                HoverableIconButton(systemName: "gearshape", helpText: "Open Preferences") {
                    openWindow(id: "preferences")
                    NSApp.activate(ignoringOtherApps: true)
                    for window in NSApp.windows where window.identifier?.rawValue == "preferences" {
                        window.makeKeyAndOrderFront(nil)
                        window.orderFrontRegardless()
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Divider().opacity(0.5)

            // MARK: 2. Sensor Tiles
            HStack(spacing: 10) {
                TempTileView(label: "CPU", temp: state.cpuTemp)
                TempTileView(label: "GPU", temp: state.gpuTemp)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            // MARK: 3. Fan RPM rows
            if !state.fans.isEmpty {
                VStack(spacing: 6) {
                    ForEach(state.fans) { fan in
                        FanRowView(fan: fan)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
            } else if state.daemonStatus == .installed {
                HStack {
                    Text("No Fans Detected")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
            }
            
            // MARK: 4. Clock Speeds
            let clocks = state.sensors.filter { $0.group == .clockSpeed }
            if !clocks.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 65), spacing: 8)], spacing: 8) {
                    ForEach(clocks) { clock in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(clock.name.uppercased())
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)
                            Text("\(Int(clock.value.rounded())) MHz")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }

            // MARK: 4. Preset Picker
            PresetPickerView(state: state)
                .padding(.horizontal, 14)
                .padding(.top, 12)

            // MARK: 5. Warning bar (conditional — daemon missing or broken)
            if state.daemonStatus == .notInstalled || state.daemonStatus == .requiresApproval || state.daemonStatus == .unreachable {
                DaemonWarningBar(status: state.daemonStatus)
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
            }

            Spacer(minLength: 8)

            // MARK: 6. Quit Button
            Divider().opacity(0.5)
            HoverableRowButton(title: "Quit CoolMyMac", shortcut: "⌘Q") {
                NSApplication.shared.terminate(nil)
            }
            .padding(.bottom, 6)
        }
        .frame(width: 320)
        .background(.regularMaterial)
        .onAppear { state.startRefreshing() }
        .onDisappear { state.stopRefreshing() }
    }
}

// MARK: - Temp Tile

struct TempTileView: View {
    let label: String
    let temp: Double?
    @AppStorage("decimalResolution") private var decimalResolution: Int = 0

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            if let t = temp {
                Text(String(format: decimalResolution == 1 ? "%.1f°C" : "%.0f°C", t))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(tempColor(t))
            } else {
                Text("N/A")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
    }

    private func tempColor(_ c: Double) -> Color {
        let minTemp = 50.0
        let maxTemp = 90.0
        let t = max(0, min(1, (c - minTemp) / (maxTemp - minTemp)))
        // Hue: 0.33 = green, 0.0 = red.
        let hue = 0.33 * (1.0 - t)
        // Ensure high contrast: darker in light mode, brighter in dark mode
        let brightness = colorScheme == .dark ? 0.95 : 0.65
        let saturation = colorScheme == .dark ? 0.85 : 1.0
        return Color(hue: hue, saturation: saturation, brightness: brightness)
    }
}

// MARK: - Fan Row

struct FanRowView: View {
    let fan: FanStatus

    var body: some View {
        HStack {
            Image(systemName: "fan")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(fan.name)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(fan.currentRPM) RPM")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
            if fan.isManaged {
                Circle().fill(.blue).frame(width: 6, height: 6)
            }
        }
    }
}

// MARK: - Preset Picker

struct PresetPickerView: View {

    var state: AppState

    // Built-in presets + up to 3 custom (only shown if defined)
    private var customProfiles: [FanProfile] { state.customProfiles }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Profile")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    // Built-in presets (System)
                    ForEach(FanProfile.allBuiltIn) { profile in
                        PresetPill(
                            label: profile.displayName,
                            isActive: state.activeProfile.id == profile.id
                        )
                        .onTapGesture { state.setProfile(profile) }
                    }

                    // Custom profiles
                    ForEach(customProfiles) { profile in
                        PresetPill(
                            label: profile.displayName,
                            isActive: state.activeProfile.id == profile.id,
                            isCustom: true
                        )
                        .onTapGesture { state.setProfile(profile) }
                    }
                }
            }
        }
    }
}

struct PresetPill: View {
    let label: String
    let isActive: Bool
    var isCustom: Bool = false
    
    @State private var isHovered = false

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: isActive ? .semibold : .regular))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                isActive
                    ? AnyShapeStyle(Color.blue.opacity(isHovered ? 0.8 : 1.0))
                    : AnyShapeStyle(Color.primary.opacity(isHovered ? 0.15 : 0.08)),
                in: Capsule()
            )
            .foregroundStyle(isActive ? .white : .primary)
            .overlay(
                isCustom && !isActive
                    ? Capsule().stroke(Color.blue.opacity(0.4), lineWidth: 1)
                    : nil
            )
            .animation(.easeInOut(duration: 0.1), value: isHovered)
            .animation(.easeInOut(duration: 0.15), value: isActive)
            .onHover { isHovered = $0 }
            .contentShape(Capsule())
    }
}

// MARK: - Daemon Warning Bar

struct DaemonWarningBar: View {

    var status: DaemonInstallStatus

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 12))
            
            if status == .requiresApproval {
                Text("Helper Tool needs approval.")
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
                Spacer()
                HoverableTextButton(title: "Open Settings") {
                    DaemonManager.shared.openSystemSettingsForApproval()
                }
            } else if status == .unreachable {
                Text("Helper Tool disconnected.")
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
                Spacer()
                HoverableTextButton(title: "Restart") {
                    Task { try? await DaemonManager.shared.repairDaemon() }
                }
            } else {
                Text("Helper Tool not installed.")
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
                Spacer()
                HoverableTextButton(title: "Install") {
                    Task { try? await DaemonManager.shared.installDaemon() }
                }
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.25), lineWidth: 1)
        )
    }
}

// MARK: - FanProfile Identifiable
// Extension removed to fix redundant conformance warning

// MARK: - Hover Components

struct HoverableRowButton: View {
    let title: String
    let shortcut: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(isHovered ? Color.white : Color.primary)
                Spacer()
                Text(shortcut)
                    .font(.system(size: 11))
                    .foregroundStyle(isHovered ? AnyShapeStyle(Color.white.opacity(0.8)) : AnyShapeStyle(.tertiary))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isHovered ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 4))
            .padding(.horizontal, 4) // Add slight margin so the highlight doesn't bleed to the very edge, mimicking macOS 11+
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

struct HoverableTextButton: View {
    let title: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .underline(isHovered)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.blue)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .contentShape(Rectangle())
    }
}

struct HoverableIconButton: View {
    let systemName: String
    let helpText: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13))
                .foregroundStyle(isHovered ? .primary : .secondary)
                .background(
                    isHovered ? Color.primary.opacity(0.1) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 4)
                )
        }
        .buttonStyle(.plain)
        .help(helpText)
        .onHover { isHovered = $0 }
        .contentShape(Rectangle())
    }
}
