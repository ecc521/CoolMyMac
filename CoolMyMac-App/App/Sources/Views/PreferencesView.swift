// PreferencesView.swift
// Preferences window with macOS Settings-style sidebar navigation.
// Sections: General, Profiles, Sensors, About

import SwiftUI
import SMCKit

struct PreferencesView: View {

    var state: AppState

    @State private var selectedSection: PrefsSection = .general

    enum PrefsSection: String, CaseIterable, Identifiable {
        case general  = "General"
        case profiles = "Profiles"
        case sensors  = "Sensors"
        case about    = "About"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .general:  return "gearshape"
            case .profiles: return "slider.horizontal.3"
            case .sensors:  return "thermometer.medium"
            case .about:    return "info.circle"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            // Sidebar
            List(PrefsSection.allCases, selection: $selectedSection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            Group {
                switch selectedSection {
                case .general:  GeneralPrefsView(state: state)
                case .profiles: ProfilesPrefsView(state: state)
                case .sensors:  SensorsPrefsView(state: state)
                case .about:    AboutPrefsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(24)
        }
        .task { state.startRefreshing() }
    }
}

// MARK: - General

struct GeneralPrefsView: View {

    var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("General")
                .font(.title2).bold()

            GroupBox("Menu Bar") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Launch CoolMyMac at login", isOn: Binding(
                        get: { state.launchAtLogin },
                        set: { state.launchAtLogin = $0 }
                    ))
                    .tint(.blue)

                    Picker("Display Mode", selection: Binding(
                        get: { state.iconDisplayMode },
                        set: { state.iconDisplayMode = $0 }
                    )) {
                        ForEach(IconDisplayMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle("Dynamic color icon (green → red based on temp)", isOn: Binding(
                        get: { state.dynamicIconEnabled },
                        set: { state.dynamicIconEnabled = $0 }
                    ))
                    .tint(.blue)
                }
                .padding(4)
            }

            GroupBox("Daemon") {
                HStack {
                    Circle()
                        .fill(daemonStatusColor)
                        .frame(width: 8, height: 8)
                    Text(daemonStatusLabel)
                        .font(.system(size: 13))

                    Spacer()

                    if state.daemonStatus == .notInstalled || state.daemonStatus == .requiresApproval {
                        Button("Install Daemon") {
                            Task { try? await DaemonManager.shared.installDaemon() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .controlSize(.small)
                    } else {
                        Button("Reload") {
                            Task { try? await DaemonManager.shared.repairDaemon() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(4)
            }
            
            GroupBox("Advanced") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Update Interval", selection: Binding(
                        get: { state.updateInterval },
                        set: { state.updateInterval = $0 }
                    )) {
                        Text("1 second").tag(1.0)
                        Text("2 seconds").tag(2.0)
                        Text("3 seconds").tag(3.0)
                        Text("5 seconds").tag(5.0)
                    }
                    .frame(width: 260)

                    Picker("Decimal places", selection: Binding(
                        get: { state.decimalResolution },
                        set: { state.decimalResolution = $0 }
                    )) {
                        Text("0 (e.g. 45°C)").tag(0)
                        Text("1 (e.g. 45.1°C)").tag(1)
                    }
                    .frame(width: 260)
                }
                .padding(4)
            }

            Spacer()
        }
    }

    private var daemonStatusColor: Color {
        switch state.daemonStatus {
        case .installed:        return .green
        case .notInstalled:     return .red
        case .requiresApproval: return .orange
        case .unreachable:      return .orange
        case .unknown:          return .gray
        }
    }

    private var daemonStatusLabel: String {
        switch state.daemonStatus {
        case .installed:        return "Daemon running"
        case .notInstalled:     return "Daemon not installed"
        case .requiresApproval: return "Approval required — click to re-grant"
        case .unreachable:      return "Daemon disconnected"
        case .unknown:          return "Status unknown"
        }
    }
}

// MARK: - Profiles

struct ProfilesPrefsView: View {

    var state: AppState
    @State private var selectedProfile: FanProfile? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Profiles")
                .font(.title2).bold()

            HStack(alignment: .top, spacing: 16) {
                // Profile list
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(FanProfile.allBuiltIn) { profile in
                        ProfileListRow(
                            profile: profile,
                            isActive: state.activeProfile.id == profile.id,
                            isSelected: selectedProfile?.id == profile.id
                        )
                        .onTapGesture {
                            selectedProfile = profile
                        }
                    }

                    Divider()

                    if state.customProfiles.isEmpty {
                        Text("Custom profiles will appear here")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 4)
                    } else {
                        ForEach(state.customProfiles) { profile in
                            ProfileListRow(
                                profile: profile,
                                isActive: state.activeProfile.id == profile.id,
                                isSelected: selectedProfile?.id == profile.id
                            )
                            .onTapGesture {
                                selectedProfile = profile
                            }
                        }
                    }

                    Spacer()

                    HStack {
                        Button(action: { createNewProfile() }) { Image(systemName: "plus") }
                            .buttonStyle(.plain)
                        Button(action: { deleteSelectedProfile() }) { Image(systemName: "minus") }
                            .buttonStyle(.plain)
                            .disabled(selectedProfile?.isBuiltIn ?? true)
                    }
                    .padding(.top, 4)
                }
                .frame(width: 180)

                // Detail panel
                if let profile = selectedProfile {
                    ProfileDetailView(profile: profile, state: state)
                } else {
                    Text("Select a profile to view details")
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private func createNewProfile() {
        let id = UUID().uuidString
        let newProfile = FanProfile(
            id: id,
            displayName: "New Profile",
            isBuiltIn: false,
            curve: FanCurve(points: [
                CurvePoint(celsius: 50.0, rpmPercentage: 0.3),
                CurvePoint(celsius: 85.0, rpmPercentage: 1.0)
            ]),
            settings: ProfileSettings()
        )
        Task {
            try? await state.client.saveCustomProfile(newProfile)
            await MainActor.run { state.startRefreshing() }
            selectedProfile = newProfile
        }
    }

    private func deleteSelectedProfile() {
        guard let p = selectedProfile, !p.isBuiltIn else { return }
        Task {
            try? await state.client.deleteCustomProfile(id: p.id)
            await MainActor.run {
                selectedProfile = nil
                state.startRefreshing()
            }
        }
    }
}

struct ProfileListRow: View {
    let profile: FanProfile
    let isActive: Bool
    let isSelected: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName)
                    .font(.system(size: 13, weight: .medium))
                Text(profile.isBuiltIn ? "Built-in" : "Custom")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isActive {
                Image(systemName: "checkmark")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
        }
        .padding(8)
        .background(isSelected ? Color.blue.opacity(0.12) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
    }
}

struct ProfileDetailView: View {
    let profile: FanProfile
    var state: AppState

    var body: some View {
        if profile.isBuiltIn {
            BuiltInProfileDetailView(profile: profile, state: state)
        } else {
            CustomProfileDetailView(profile: profile, state: state)
                .id(profile.id) // Force view redraw when selecting a different custom profile
        }
    }
}

struct BuiltInProfileDetailView: View {
    let profile: FanProfile
    var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(profile.displayName)
                    .font(.headline)
                Spacer()
                Button("Activate") {
                    state.setProfile(profile)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(state.activeProfile.id == profile.id)
                .controlSize(.small)
            }

            // Settings summary
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("Sensor sources").foregroundStyle(.secondary).font(.system(size: 12))
                    Text(profile.settings.sources.map(\.rawValue).joined(separator: ", ")).font(.system(size: 12))
                }
                GridRow {
                    Text("Aggregation").foregroundStyle(.secondary).font(.system(size: 12))
                    Text(profile.settings.aggregation.rawValue).font(.system(size: 12))
                }
                GridRow {
                    Text("Smoothing").foregroundStyle(.secondary).font(.system(size: 12))
                    Text("\(profile.settings.smoothingWindowSeconds, specifier: "%.0f")s").font(.system(size: 12))
                }
            }

            // Curve
            if profile.curve.points.isEmpty {
                Text("No fan curve — Apple manages fans automatically.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                Text("Fan Curve")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                VStack(spacing: 4) {
                    ForEach(Array(profile.curve.points.enumerated()), id: \.offset) { _, point in
                        HStack {
                            Text(String(format: "%.0f°C", point.celsius))
                                .font(.system(size: 12, design: .monospaced))
                                .frame(width: 48, alignment: .leading)
                            CurveBar(percentage: point.rpmPercentage)
                            Text("\(Int(point.rpmPercentage * 100))%")
                                .font(.system(size: 12, design: .monospaced))
                                .frame(width: 48, alignment: .trailing)
                        }
                    }
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct CustomProfileDetailView: View {
    let profile: FanProfile
    var state: AppState

    @State private var displayName: String
    @State private var editablePoints: [EditablePoint]

    struct EditablePoint: Identifiable {
        let id = UUID()
        var celsius: Double
        var rpmPercentage: Double
    }

    init(profile: FanProfile, state: AppState) {
        self.profile = profile
        self.state = state
        self._displayName = State(initialValue: profile.displayName)
        let mapped = profile.curve.points.map { EditablePoint(celsius: $0.celsius, rpmPercentage: $0.rpmPercentage) }
        self._editablePoints = State(initialValue: mapped)
    }

    private var hasChanges: Bool {
        if displayName != profile.displayName { return true }
        if editablePoints.count != profile.curve.points.count { return true }
        for (i, ep) in editablePoints.enumerated() {
            let op = profile.curve.points[i]
            if ep.celsius != op.celsius || ep.rpmPercentage != op.rpmPercentage { return true }
        }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                TextField("Profile Name", text: $displayName)
                    .font(.headline)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)

                Spacer()

                if hasChanges {
                    Button("Save") {
                        let sorted = editablePoints.sorted(by: { $0.celsius < $1.celsius })
                        let newPoints = sorted.map { CurvePoint(celsius: $0.celsius, rpmPercentage: $0.rpmPercentage) }
                        let newProfile = FanProfile(
                            id: profile.id,
                            displayName: displayName,
                            isBuiltIn: false,
                            curve: FanCurve(points: newPoints),
                            settings: profile.settings
                        )
                        Task { try? await state.client.saveCustomProfile(newProfile); state.startRefreshing() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.small)
                }

                Button("Activate") {
                    state.setProfile(profile)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(state.activeProfile.id == profile.id || hasChanges)
                .controlSize(.small)
            }

            Text("Fan Curve")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach($editablePoints.indices, id: \.self) { i in
                    HStack {
                        TextField("Temp", value: $editablePoints[i].celsius, format: .number)
                            .frame(width: 50)
                            .textFieldStyle(.roundedBorder)
                        Text("°C")
                            .font(.system(size: 12))

                        Spacer().frame(width: 20)

                        TextField("Speed", value: Binding(get: {
                            editablePoints[i].rpmPercentage * 100
                        }, set: { new in
                            editablePoints[i].rpmPercentage = new / 100.0
                        }), format: .number)
                            .frame(width: 50)
                            .textFieldStyle(.roundedBorder)
                        Text("%")
                            .font(.system(size: 12))

                        Button(action: {
                            editablePoints.remove(at: i)
                        }) {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 8)
                        
                        CurveBar(percentage: editablePoints[i].rpmPercentage)
                            .frame(maxWidth: 80)
                            .padding(.leading, 12)
                    }
                }

                Button(action: {
                    let lastT = editablePoints.last?.celsius ?? 40.0
                    let lastP = editablePoints.last?.rpmPercentage ?? 0.3
                    editablePoints.append(EditablePoint(celsius: lastT + 10, rpmPercentage: lastP + 0.1))
                }) {
                    Label("Add Point", systemImage: "plus.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                .font(.system(size: 12))
                .padding(.top, 4)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct CurveBar: View {
    let percentage: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(Color.blue.opacity(0.7))
                    .frame(width: geo.size.width * CGFloat(percentage))
            }
        }
        .frame(height: 6)
    }
}

// MARK: - Sensors

struct SensorsPrefsView: View {
    var state: AppState
    @AppStorage("decimalResolution") private var decimalResolution: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Live Sensors")
                .font(.title2).bold()

            if state.sensors.isEmpty {
                Text("Waiting for sensor data from daemon...")
                    .foregroundStyle(.tertiary)
            } else {
                let grouped = Dictionary(grouping: state.sensors, by: \.group)
                let order: [SensorGroup] = [.cpuCore, .gpu, .nand, .other]

                ForEach(order, id: \.self) { group in
                    if let sensors = grouped[group] {
                        Section {
                            ForEach(sensors.sorted(by: { $0.celsius > $1.celsius })) { s in
                                HStack {
                                    Text(s.name).font(.system(size: 12))
                                    Spacer()
                                    Text(String(format: decimalResolution == 1 ? "%.1f°C" : "%.0f°C", s.celsius))
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(s.celsius > 80 ? .orange : .primary)
                                }
                                .padding(.vertical, 2)
                            }
                        } header: {
                            HStack {
                                Text(group.rawValue)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                
                                Spacer()
                                
                                Toggle("Use for fan control", isOn: Binding(
                                    get: { state.activeSensors.contains(group) },
                                    set: { isOn in
                                        if isOn {
                                            state.activeSensors.insert(group)
                                        } else if state.activeSensors.count > 1 {
                                            state.activeSensors.remove(group)
                                        }
                                    }
                                ))
                                .controlSize(.mini)
                                .tint(.blue)
                            }
                            .padding(.top, 8)
                            .padding(.bottom, 4)
                        }
                    }
                }
            }

            Spacer()
        }
    }
}

// MARK: - About

struct AboutPrefsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "wind")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
            Text("CoolMyMac")
                .font(.title.bold())
            Text("Version 1.0.0")
                .foregroundStyle(.secondary)
            Text("Advanced fan control for macOS 15+")
                .foregroundStyle(.secondary)
                .font(.system(size: 13))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
