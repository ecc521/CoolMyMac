// PreferencesView.swift
// Preferences window with macOS Settings-style sidebar navigation.
// Sections: General, Profiles, Sensors, About

import SwiftUI
import SMCKit
import ServiceManagement

struct PreferencesView: View {

    var state: AppState
    @State private var isCLIInstalled: Bool = false

    @State private var selectedSection: PrefsSection = .general

    enum PrefsSection: String, CaseIterable, Identifiable {
        case general  = "General"
        case profiles = "Profiles"
        case sensors  = "Sensors"
        case cli      = "CLI"
        case about    = "About"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .general:  return "gearshape"
            case .profiles: return "slider.horizontal.3"
            case .sensors:  return "thermometer.medium"
            case .cli:      return "terminal"
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
                case .cli:      CLIPrefsView(state: state)
                case .about:    AboutPrefsView()
                }
            }
            .frame(minWidth: 400, idealWidth: 500, maxWidth: .infinity, minHeight: 300, idealHeight: 400, maxHeight: .infinity, alignment: .topLeading)
            .padding(24)
        }
        .onAppear { state.startRefreshing() }
        .onDisappear { state.stopRefreshing() }
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows where window.identifier?.rawValue == "preferences" {
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
        }
    }
}

// MARK: - General

struct GeneralPrefsView: View {

    var state: AppState
    @State private var isCLIInstalled: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("General")
                    .font(.title2).bold()

            if state.updateChecker.updateAvailable {
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.blue)
                        .imageScale(.large)
                    
                    VStack(alignment: .leading) {
                        Text("Update Available: v\(state.updateChecker.latestVersion)")
                            .font(.headline)
                        Text("A newer version of CoolMyMac is available on GitHub.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    if let url = state.updateChecker.releaseUrl {
                        Button("Download") {
                            NSWorkspace.shared.open(url)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(10)
            }
            
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

            GroupBox("Helper Tool") {
                HStack {
                    Circle()
                        .fill(daemonStatusColor)
                        .frame(width: 8, height: 8)
                    Text(daemonStatusLabel)
                        .font(.system(size: 13))

                    Spacer()

                    if state.daemonStatus == .notInstalled {
                        Button("Install") {
                            Task { try? await DaemonManager.shared.installDaemon() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .controlSize(.small)
                    } else if state.daemonStatus == .requiresApproval {
                        Button("Open Settings") {
                            SMAppService.openSystemSettingsLoginItems()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
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
                Form {
                    Picker("Update Interval:", selection: Binding(
                        get: { state.updateInterval },
                        set: { state.updateInterval = $0 }
                    )) {
                        Text("1 second").tag(1.0)
                        Text("2 seconds").tag(2.0)
                        Text("3 seconds").tag(3.0)
                        Text("5 seconds").tag(5.0)
                    }

                    Picker("Decimal places:", selection: Binding(
                        get: { state.decimalResolution },
                        set: { state.decimalResolution = $0 }
                    )) {
                        Text("0 (e.g. 45°C)").tag(0)
                        Text("1 (e.g. 45.1°C)").tag(1)
                    }
                }
                .padding(4)
            }

            Spacer()
        }
        .padding(.trailing, 8) // Give scrollbar breathing room
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
        case .installed:        
            if let ver = state.daemonVersion { return "Helper Tool running (v\(ver))" }
            return "Helper Tool running"
        case .notInstalled:     return "Helper Tool required"
        case .requiresApproval: return "Background permission missing"
        case .unreachable:      return "Helper Tool disconnected"
        case .unknown:          return "Status unknown"
        }
    }
}

// MARK: - Profiles

struct ProfilesPrefsView: View {

    var state: AppState
    @State private var isCLIInstalled: Bool = false
    @State private var selectedProfile: FanProfile? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Profiles")
                .font(.title2).bold()

            HStack(alignment: .top, spacing: 16) {
                // Profile list
                VStack(alignment: .leading, spacing: 8) {
                    ScrollView {
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
                        }
                    }
                    
                    Spacer(minLength: 0)

                    HStack {
                        Button(action: { createNewProfile() }) { 
                            Image(systemName: "plus")
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Button(action: { deleteSelectedProfile() }) { 
                            Image(systemName: "minus")
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(selectedProfile?.isBuiltIn ?? true)
                            
                        Spacer()
                        
                        Button(action: { moveProfile(direction: -1) }) { 
                            Image(systemName: "chevron.up")
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(selectedProfile?.isBuiltIn ?? true)

                        Button(action: { moveProfile(direction: 1) }) { 
                            Image(systemName: "chevron.down")
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(selectedProfile?.isBuiltIn ?? true)
                    }
                    .padding(.top, 4)
                }
                .frame(width: 180)

                // Detail panel
                if let profile = selectedProfile {
                    ScrollView {
                        ProfileDetailView(profile: profile, state: state, onDelete: {
                            deleteSelectedProfile()
                        }, onSave: { newProfile in
                            selectedProfile = newProfile
                        })
                        .padding(.trailing, 8)
                        .padding(.bottom, 24)
                        .frame(maxWidth: .infinity, alignment: .top)
                    }
                } else {
                    Text("Select a profile to view details")
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private func moveProfile(direction: Int) {
        guard let profile = selectedProfile, !profile.isBuiltIn else { return }
        state.moveProfile(id: profile.id, direction: direction)
    }

    private func createNewProfile() {
        let id = UUID().uuidString
        let newProfile = FanProfile(
            id: id,
            displayName: "New Profile",
            isBuiltIn: false,
            curve: FanCurve(points: [
                CurvePoint(value: 50.0, rpmPercentage: 0.3),
                CurvePoint(value: 85.0, rpmPercentage: 1.0)
            ]),
            settings: ProfileSettings()
        )
        Task {
            try? await state.client.saveCustomProfile(newProfile)
            await MainActor.run { state.refresh() }
            selectedProfile = newProfile
        }
    }

    private func deleteSelectedProfile() {
        guard let p = selectedProfile, !p.isBuiltIn else { return }
        
        // Optimistic UI update for instant feedback
        selectedProfile = nil
        
        Task {
            try? await state.client.deleteCustomProfile(id: p.id)
            await MainActor.run {
                state.refresh()
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
    @State private var isCLIInstalled: Bool = false
    var onDelete: (() -> Void)? = nil
    var onSave: ((FanProfile) -> Void)? = nil

    var body: some View {
        if profile.isBuiltIn {
            BuiltInProfileDetailView(profile: profile, state: state)
        } else {
            CustomProfileDetailView(profile: profile, state: state, onSave: onSave, onDelete: onDelete)
                .id(profile.id) // Force view redraw when selecting a different custom profile
        }
    }
}

struct BuiltInProfileDetailView: View {
    let profile: FanProfile
    var state: AppState
    @State private var isCLIInstalled: Bool = false

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

            if profile.curve.points.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Hardware Managed")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    
                    Text("This profile returns full thermal control to macOS without applying any fan overrides.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 8)
            } else {
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
                        Text("Spin Up Smoothing").foregroundStyle(.secondary).font(.system(size: 12))
                        Text("\(profile.settings.spinUpTime, specifier: "%.1f")s").font(.system(size: 12))
                    }
                    GridRow {
                        Text("Spin Down Smoothing").foregroundStyle(.secondary).font(.system(size: 12))
                        Text("\(profile.settings.spinDownTime, specifier: "%.1f")s").font(.system(size: 12))
                    }
                }

                Text("Fan Curve")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)

                VStack(spacing: 4) {
                    ForEach(Array(profile.curve.points.enumerated()), id: \.offset) { _, point in
                        HStack {
                            Text(String(format: "%.0f°C", point.value))
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
    @State private var isCLIInstalled: Bool = false
    var onSave: ((FanProfile) -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    @State private var displayName: String
    @State private var editablePoints: [EditablePoint]
    @State private var spinUpTime: Double
    @State private var spinDownTime: Double
    @State private var selectedSources: Set<SensorGroup>
    @State private var aggregation: AggregationMode
    @State private var showError: Bool = false
    @State private var errorMessage: String?

    struct EditablePoint: Identifiable {
        let id = UUID()
        var value: Double
        var rpmPercentage: Double
    }

    init(profile: FanProfile, state: AppState, onSave: ((FanProfile) -> Void)? = nil, onDelete: (() -> Void)? = nil) {
        self.profile = profile
        self.state = state
        self.onSave = onSave
        self.onDelete = onDelete
        self._displayName = State(initialValue: profile.displayName)
        let mapped = profile.curve.points.map { EditablePoint(value: $0.value, rpmPercentage: $0.rpmPercentage) }
        self._editablePoints = State(initialValue: mapped)
        self._spinUpTime = State(initialValue: profile.settings.spinUpTime)
        self._spinDownTime = State(initialValue: profile.settings.spinDownTime)
        self._selectedSources = State(initialValue: Set(profile.settings.sources))
        self._aggregation = State(initialValue: profile.settings.aggregation)
    }

    private var hasChanges: Bool {
        if displayName != profile.displayName { return true }
        if spinUpTime != profile.settings.spinUpTime { return true }
        if spinDownTime != profile.settings.spinDownTime { return true }
        if aggregation != profile.settings.aggregation { return true }
        if Set(profile.settings.sources) != selectedSources { return true }
        if editablePoints.count != profile.curve.points.count { return true }
        for (i, ep) in editablePoints.enumerated() {
            let op = profile.curve.points[i]
            if ep.value != op.value || ep.rpmPercentage != op.rpmPercentage { return true }
        }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                TextField("Profile Name", text: $displayName)
                    .font(.headline)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)

                Spacer()

                if hasChanges {
                    Button("Save Changes") {
                        let sorted = editablePoints.sorted(by: { $0.value < $1.value })
                        let newPoints = sorted.map { CurvePoint(value: $0.value, rpmPercentage: $0.rpmPercentage) }
                        let finalSources = selectedSources.isEmpty ? [.cpuCore] : Array(selectedSources)
                        let newSettings = ProfileSettings(
                            sources: finalSources,
                            aggregation: aggregation,
                            spinUpTime: spinUpTime,
                            spinDownTime: spinDownTime
                        )
                        let newProfile = FanProfile(
                            id: profile.id,
                            displayName: displayName,
                            isBuiltIn: false,
                            curve: FanCurve(points: newPoints),
                            settings: newSettings
                        )
                        Task { 
                            do {
                                try await state.client.saveCustomProfile(newProfile)
                                await MainActor.run { 
                                    state.refresh()
                                    onSave?(newProfile)
                                }
                            } catch {
                                await MainActor.run {
                                    errorMessage = error.localizedDescription
                                    showError = true
                                }
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.small)
                    .alert("Error Saving Profile", isPresented: $showError, presenting: errorMessage) { _ in
                        Button("OK", role: .cancel) {}
                    } message: { msg in
                        Text(msg)
                    }
                } else {
                    Button("Activate") {
                        state.setProfile(profile)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(state.activeProfile.id == profile.id)
                    .controlSize(.small)
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("Sensor Targets").foregroundStyle(.secondary).font(.system(size: 12))
                    Menu {
                        ForEach([SensorGroup.cpuCore, .gpu, .battery, .enclosure], id: \.self) { group in
                            Button {
                                if selectedSources.contains(group) {
                                    selectedSources.remove(group)
                                } else {
                                    selectedSources.insert(group)
                                }
                            } label: {
                                HStack {
                                    Text(group.rawValue)
                                    if selectedSources.contains(group) {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Text(selectedSources.isEmpty ? SensorGroup.cpuCore.rawValue : selectedSources.map(\.rawValue).joined(separator: ", "))
                            .lineLimit(1)
                    }
                    .frame(width: 140)
                }
                GridRow {
                    Text("Aggregation Mode").foregroundStyle(.secondary).font(.system(size: 12))
                    Picker("", selection: $aggregation) {
                        Text("Max (Hottest)").tag(AggregationMode.max)
                        Text("Average").tag(AggregationMode.average)
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }
                GridRow {
                    Text("Spin Up Time (EMA)").foregroundStyle(.secondary).font(.system(size: 12))
                    HStack {
                        TextField("Sec", value: $spinUpTime, format: .number)
                            .textFieldStyle(.roundedBorder).frame(width: 40)
                            .font(.system(size: 12))
                        Text("s").font(.caption).foregroundStyle(.secondary)
                    }
                }
                GridRow {
                    Text("Spin Down Time (EMA)").foregroundStyle(.secondary).font(.system(size: 12))
                    HStack {
                        TextField("Sec", value: $spinDownTime, format: .number)
                            .textFieldStyle(.roundedBorder).frame(width: 40)
                            .font(.system(size: 12))
                        Text("s").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Text("Fan Curve")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach($editablePoints.indices, id: \.self) { i in
                    HStack {
                        TextField("Temp", value: $editablePoints[i].value, format: .number)
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
                    let lastT = editablePoints.last?.value ?? 40.0
                    let lastP = editablePoints.last?.rpmPercentage ?? 0.3
                    editablePoints.append(EditablePoint(value: lastT + 10, rpmPercentage: lastP + 0.1))
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
    @State private var isCLIInstalled: Bool = false
    @AppStorage("decimalResolution") private var decimalResolution: Int = 0
    @State private var expandedGroups: Set<SensorGroup> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .lastTextBaseline) {
                Text("Live Sensors")
                    .font(.title2).bold()
                
                Spacer()
                
                if let lastUpdate = state.lastSensorsUpdate {
                    TimelineView(.periodic(from: .now, by: 1.0)) { timeline in
                        let elapsed = Int(timeline.date.timeIntervalSince(lastUpdate))
                        let timeString = elapsed < 3 ? "just now" : "\(elapsed)s ago"
                        Text("Updated \(timeString)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if state.sensors.isEmpty {
                if state.daemonStatus == .installed {
                    Text("Waiting for sensor data from helper tool...")
                        .foregroundStyle(.tertiary)
                } else {
                    Text("Helper tool required for sensors. Please install the helper tool in the General tab.")
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            } else {
                List {
                    let grouped = Dictionary(grouping: state.sensors, by: \.group)
                    // Sensor Group Display Order (Labeled by Architecture Support):
                    // - .power: Both (Intel: package_watts; Apple Silicon: combined/cpu/gpu mW)
                    // - .clockSpeed: Both (Intel: core/package/GPU freqs; Apple Silicon: cluster/GPU freqs)
                    // - .cpuCore: Both (Intel: TCxx keys; Apple Silicon: Tpxx/cores)
                    // - .gpu: Both (Intel: TGxx keys; Apple Silicon: Tgxx/GPU core)
                    // - .vrm: Both (Intel: TPCD/Power/PCH; Apple Silicon: VRM keys)
                    // - .wireless: Intel-only (TWxx wifi keys)
                    // - .battery: Both (Intel: TBxx keys; Apple Silicon: TBxx keys)
                    // - .enclosure: Both (Intel: heatsink/ambient/skin; Apple Silicon: skin/ambient)
                    // - .nand: Both (Intel: TNxx keys; Apple Silicon: Tnxx keys)
                    // - .other: Both
                    let order: [SensorGroup] = [.power, .clockSpeed, .cpuCore, .gpu, .limits, .vrm, .wireless, .battery, .enclosure, .nand, .other]

                    ForEach(order, id: \.self) { group in
                        if let sensors = grouped[group] {
                            let maxValue = sensors.map(\.value).max() ?? 0.0
                            let minValue = sensors.map(\.value).min() ?? 0.0
                            let unit = sensors.first?.unit ?? .celsius
                            
                            DisclosureGroup(
                                isExpanded: Binding(
                                    get: { expandedGroups.contains(group) },
                                    set: { if $0 { expandedGroups.insert(group) } else { expandedGroups.remove(group) } }
                                )
                            ) {
                                ForEach(sensors.sorted(by: { $0.value > $1.value })) { s in
                                    SensorRowView(
                                        sensor: s,
                                        group: group,
                                        state: state,
                                        decimalResolution: decimalResolution
                                    )
                                }
                            } label: {
                                HStack {
                                    HStack {
                                        Text(group.rawValue)
                                            .font(.system(size: 12, weight: .semibold))
                                            .textCase(.uppercase)
                                            .foregroundStyle(.primary)
                                        
                                        Spacer()
                                        
                                        Text(String(format: rangeFormat(for: unit), minValue, maxValue))
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .padding(.trailing, 8)
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if expandedGroups.contains(group) {
                                            expandedGroups.remove(group)
                                        } else {
                                            expandedGroups.insert(group)
                                        }
                                    }
                                    

                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .cornerRadius(8)
            }
        }
        .onAppear { state.isViewingAllSensors = true }
        .onDisappear { state.isViewingAllSensors = false }
    }
    
    private func rangeFormat(for unit: SensorUnit) -> String {
        switch unit {
        case .celsius: return decimalResolution == 1 ? "%.1f - %.1f°C" : "%.0f - %.0f°C"
        case .watts: return "%.2f - %.2f W"
        case .megahertz: return "%.0f - %.0f MHz"
        case .percentage: return "%.0f - %.0f%%"
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
            if let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                Text("Version \(appVersion)")
                    .foregroundStyle(.secondary)
            }
            Text("Advanced fan control for macOS 15+")
                .foregroundStyle(.secondary)
                .font(.system(size: 13))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct SensorRowView: View {
    let sensor: SensorReading
    let group: SensorGroup
    @Bindable var state: AppState
    @State private var isCLIInstalled: Bool = false
    let decimalResolution: Int
    
    private var formatString: String {
        switch sensor.unit {
        case .celsius: return decimalResolution == 1 ? "%.1f°C" : "%.0f°C"
        case .watts: return "%.2f W"
        case .megahertz: return "%.0f MHz"
        case .percentage: return "%.0f%%"
        }
    }
    
    var body: some View {
        let isPowerOrClock = (group == .power || group == .clockSpeed)
        let isExcluded = !isPowerOrClock && !state.activeSensors.contains(group)
        let isHot = sensor.unit == .celsius && sensor.value > 80
        
        HStack {
            Text(sensor.name)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .opacity(isExcluded ? 0.5 : 1.0)
                
            Spacer()
            
            Text(String(format: formatString, sensor.value))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(isHot ? Color.orange : Color.primary)
                .opacity(isExcluded ? 0.5 : 1.0)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - CLI

struct CLIPrefsView: View {

    var state: AppState
    @State private var isCLIInstalled: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Command Line Tool")
                    .font(.title2).bold()

                GroupBox("Command Line Tool") {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("coolmymac")
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            Text("Control profiles and fans directly from the terminal.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        if isCLIInstalled {
                            HStack(spacing: 12) {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    Text("Installed")
                                        .font(.system(size: 13))
                                }
                                Button("Uninstall CLI") {
                                    uninstallCLI()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        } else {
                            Button("Install CLI") {
                                installCLI()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(4)
                    
                    Form {
                        Toggle("Allow Unprivileged CLI", isOn: Binding(
                            get: { state.allowUnprivilegedCLI },
                            set: { state.setAllowUnprivilegedCLI($0) }
                        ))
                        .help("Allows standard terminal commands to change profiles without requiring sudo.")
                    }
                    .padding(4)

                    if isCLIInstalled {
                        Divider()

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Common Commands")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)

                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 6) {
                                    Text("coolmymac --help")
                                        .font(.system(size: 11, design: .monospaced))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.primary.opacity(0.05))
                                        .cornerRadius(4)
                                    
                                    Button(action: { runInTerminal("coolmymac --help") }) {
                                        Image(systemName: "terminal")
                                            .font(.system(size: 10))
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.blue)
                                    .help("Run in Terminal")
                                    
                                    Text("Show available commands and options")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                HStack(spacing: 6) {
                                    Text("coolmymac fans")
                                        .font(.system(size: 11, design: .monospaced))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.primary.opacity(0.05))
                                        .cornerRadius(4)
                                    
                                    Button(action: { runInTerminal("coolmymac fans") }) {
                                        Image(systemName: "terminal")
                                            .font(.system(size: 10))
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.blue)
                                    .help("Run in Terminal")
                                    
                                    Text("Display live fan speeds and status")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                HStack(spacing: 6) {
                                    Text("coolmymac profile set balanced")
                                        .font(.system(size: 11, design: .monospaced))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.primary.opacity(0.05))
                                        .cornerRadius(4)
                                    
                                    Button(action: { runInTerminal("coolmymac profile set balanced") }) {
                                        Image(systemName: "terminal")
                                            .font(.system(size: 10))
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.blue)
                                    .help("Run in Terminal")
                                    
                                    Text("Activate a specific fan profile")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                HStack(spacing: 6) {
                                    Text("coolmymac reset")
                                        .font(.system(size: 11, design: .monospaced))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.primary.opacity(0.05))
                                        .cornerRadius(4)
                                    
                                    Button(action: { runInTerminal("coolmymac reset") }) {
                                        Image(systemName: "terminal")
                                            .font(.system(size: 10))
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.blue)
                                    .help("Run in Terminal")
                                    
                                    Text("Reset all fans back to Apple auto control")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Text("Installed at: /usr/local/bin/coolmymac")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding(.top, 6)
                        }
                        .padding(4)
                    }
                }
                .onAppear {
                    checkCLIStatus()
                }
            }
            .padding()
        }
    }

    private func checkCLIStatus() {
        let symlinkPath = "/usr/local/bin/coolmymac"
        guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: symlinkPath) else {
            isCLIInstalled = false
            return
        }
        guard let myExecPath = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("coolmymac-cli").path else {
            isCLIInstalled = false
            return
        }
        isCLIInstalled = (destination == myExecPath)
    }
    
    private func installCLI() {
        Task {
            do {
                try await state.client.installCLI()
                await MainActor.run {
                    checkCLIStatus()
                }
            } catch {
                print("Failed to install CLI: \(error.localizedDescription)")
            }
        }
    }

    private func uninstallCLI() {
        Task {
            do {
                try await state.client.uninstallCLI()
                await MainActor.run {
                    checkCLIStatus()
                }
            } catch {
                print("Failed to uninstall CLI: \(error.localizedDescription)")
            }
        }
    }

    private func runInTerminal(_ command: String) {
        let fileManager = FileManager.default
        let tempDirectory = fileManager.temporaryDirectory
        let commandFileURL = tempDirectory.appendingPathComponent("coolmymac_run.command")
        
        let scriptContent = """
        #!/bin/bash
        echo "=== CoolMyMac CLI Execute ==="
        echo "Running: \(command)"
        echo ""
        if command -v coolmymac &> /dev/null; then
            \(command)
        else
            echo "Error: coolmymac is not in your PATH or is not installed."
            echo "Please make sure /usr/local/bin is in your shell PATH."
        fi
        echo ""
        echo "Press any key to close this window..."
        read -n 1
        """
        
        do {
            try scriptContent.write(to: commandFileURL, atomically: true, encoding: .utf8)
            var attributes = try fileManager.attributesOfItem(atPath: commandFileURL.path)
            let permissions = attributes[.posixPermissions] as? UInt16 ?? 0o644
            attributes[.posixPermissions] = permissions | 0o111
            try fileManager.setAttributes(attributes, ofItemAtPath: commandFileURL.path)
            
            NSWorkspace.shared.open(commandFileURL)
        } catch {
            print("Failed to run in Terminal: \(error.localizedDescription)")
        }
    }
}
