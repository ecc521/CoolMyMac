// MenuBarIconView.swift
// The icon shown in the menu bar — supports icon-only, +temp, +RPM, and dynamic color.

import SwiftUI
import SMCKit

struct MenuBarIconView: View {

    var state: AppState

    private static let minTemp = 60.0
    private static let maxTemp = 90.0

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "wind")
                .symbolRenderingMode(state.dynamicIconEnabled ? .palette : .monochrome)
                .foregroundStyle(
                    state.dynamicIconEnabled ? thermalColor : Color.primary,
                    state.dynamicIconEnabled ? thermalColor.opacity(0.6) : Color.primary
                )
                .font(.system(size: 14, weight: .medium))

            switch state.iconDisplayMode {
            case .iconOnly:
                EmptyView()
            case .iconAndTemp:
                if let temp = state.cpuTemp {
                    Text(String(format: "%.0f°", temp))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(state.dynamicIconEnabled ? thermalColor : Color.primary)
                }
            case .iconAndRPM:
                if let rpm = state.fans.first?.currentRPM {
                    Text("\(rpm)")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(state.dynamicIconEnabled ? thermalColor : Color.primary)
                }
            }
        }
    }

    /// Continuous green→red gradient across 60–90°C using hue interpolation.
    private var thermalColor: Color {
        let temp = state.hottestTemp
        let t = max(0, min(1, (temp - Self.minTemp) / (Self.maxTemp - Self.minTemp)))
        // Hue: 0.33 = green, 0.0 = red. Shift linearly.
        let hue = 0.33 * (1.0 - t)
        return Color(hue: hue, saturation: 0.9, brightness: 0.85)
    }
}
