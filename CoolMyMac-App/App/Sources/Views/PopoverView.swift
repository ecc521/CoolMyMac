// PopoverView.swift
// The main popover shown when the user clicks the menu bar icon.
// ~320pt wide. No title bar. Native frosted glass material.

import SwiftUI
import SMCKit

struct PopoverView: View {

    var state: AppState
    var onOpenPreferences: () -> Void

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
                Button {
                    onOpenPreferences()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Open Preferences")
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
            }

            // MARK: 4. Preset Picker
            PresetPickerView(state: state)
                .padding(.horizontal, 14)
                .padding(.top, 12)

            // MARK: 5. Warning bar (conditional — daemon denied)
            if state.daemonStatus == .requiresApproval {
                DaemonWarningBar()
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
            }

            Spacer(minLength: 12)
        }
        .frame(width: 320)
        .background(.regularMaterial)
        .task { state.startRefreshing() }
        .onDisappear { state.stopRefreshing() }
    }
}

// MARK: - Temp Tile

struct TempTileView: View {
    let label: String
    let temp: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            if let t = temp {
                Text(String(format: "%.1f°C", t))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(tempColor(t))
            } else {
                Text("N/A")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }

    private func tempColor(_ c: Double) -> Color {
        if c < 60 { return .primary }
        if c < 80 { return .orange }
        return .red
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
    private var customProfiles: [FanProfile] { [] }  // Phase 4: loaded from ProfileStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Profile")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            // Built-in presets
            HStack(spacing: 6) {
                ForEach(FanProfile.allBuiltIn) { profile in
                    PresetPill(
                        label: profile.displayName,
                        isActive: state.activeProfile.id == profile.id
                    )
                    .onTapGesture { state.setProfile(profile) }
                }
            }

            // Custom slots (only visible if custom profiles exist)
            if !customProfiles.isEmpty {
                HStack(spacing: 6) {
                    ForEach(customProfiles.prefix(3)) { profile in
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

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: isActive ? .semibold : .regular))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                isActive
                    ? AnyShapeStyle(Color.blue)
                    : AnyShapeStyle(Color.primary.opacity(0.08)),
                in: Capsule()
            )
            .foregroundStyle(isActive ? .white : .primary)
            .overlay(
                isCustom && !isActive
                    ? Capsule().stroke(Color.blue.opacity(0.4), lineWidth: 1)
                    : nil
            )
            .animation(.easeInOut(duration: 0.15), value: isActive)
    }
}

// MARK: - Daemon Warning Bar

struct DaemonWarningBar: View {

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 12))
            Text("Daemon not installed — fan control inactive.")
                .font(.system(size: 11))
                .foregroundStyle(.primary)
            Spacer()
            Button("Grant Permission") {
                DaemonManager.shared.openSystemSettingsForApproval()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.blue)
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
extension FanProfile: @retroactive Identifiable {}
