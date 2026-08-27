// MenuBarIconView.swift
// The icon shown in the menu bar — supports icon-only, +temp, +RPM, and dynamic color.

import AppKit
import SwiftUI
import SMCKit
import os

struct MenuBarIconView: View {

    var state: AppState
    @AppStorage("decimalResolution") private var decimalResolution: Int = 0
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    private static let minTemp = 60.0
    private static let maxTemp = 90.0
    private static let logger = Logger(subsystem: "com.coolmymac.app", category: "MenuBarIconView")

    private var usesVerticalLayout: Bool {
        state.menuBarItemLayout == .vertical && state.iconDisplayMode != .iconOnly
    }

    var body: some View {
        Image(nsImage: renderedImage)
            .renderingMode(.original)
            .accessibilityLabel(Text(accessibilityLabel))
    }

    private var renderedImage: NSImage {
        let renderer = ImageRenderer(content: labelContent.environment(\.colorScheme, colorScheme))
        renderer.scale = displayScale
        guard let image = renderer.nsImage else {
            Self.logger.error("Failed to render the menu bar label")
            let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
                .applying(NSImage.SymbolConfiguration(hierarchicalColor: .labelColor))
            let fallback = NSImage(systemSymbolName: "wind", accessibilityDescription: "CoolMyMac")?
                .withSymbolConfiguration(configuration) ?? NSImage(size: NSSize(width: 14, height: 14))
            fallback.isTemplate = false
            return fallback
        }
        image.isTemplate = false
        return image
    }

    @ViewBuilder
    private var labelContent: some View {
        if usesVerticalLayout {
            VStack(spacing: -2) {
                content
            }
            .fixedSize()
        } else {
            HStack(spacing: 2) {
                content
            }
            .fixedSize()
        }
    }

    @ViewBuilder
    private var content: some View {
        Image(systemName: "wind")
            .symbolRenderingMode(state.dynamicIconEnabled ? .palette : .monochrome)
            .foregroundStyle(
                state.dynamicIconEnabled ? thermalColor : Color.primary,
                state.dynamicIconEnabled ? thermalColor.opacity(0.6) : Color.primary
            )
            .font(.system(size: usesVerticalLayout ? 11 : 14, weight: .medium))

        switch state.iconDisplayMode {
        case .iconOnly:
            EmptyView()
        case .iconAndTemp:
            reading(
                state.cpuTemp.map { String(format: temperatureFormat, $0) } ?? "",
                anchor: temperatureAnchor
            )
        case .iconAndRPM:
            reading(state.fans.first.map { "\($0.currentRPM)" } ?? "", anchor: "99999")
        }
    }

    private var temperatureFormat: String {
        if usesVerticalLayout {
            return decimalResolution == 1 ? "%.1f" : "%.0f"
        }
        return decimalResolution == 1 ? "%.1f°" : "%.0f°"
    }

    private var temperatureAnchor: String {
        if usesVerticalLayout {
            return decimalResolution == 1 ? "100.0" : "100"
        }
        return decimalResolution == 1 ? "100.0°" : "100°"
    }

    private func reading(_ value: String, anchor: String) -> some View {
        readingText(anchor)
            .opacity(0)
            .accessibilityHidden(true)
            .overlay {
                readingText(value)
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(Color.primary)
    }

    private func readingText(_ value: String) -> some View {
        Text(value)
            .font(.system(size: usesVerticalLayout ? 9 : 12, weight: .medium, design: .monospaced))
            .monospacedDigit()
    }

    private var accessibilityLabel: String {
        switch state.iconDisplayMode {
        case .iconOnly:
            return "CoolMyMac"
        case .iconAndTemp:
            guard let temp = state.cpuTemp else { return "CoolMyMac, CPU temperature unavailable" }
            let value = String(format: decimalResolution == 1 ? "%.1f°" : "%.0f°", temp)
            return "CoolMyMac, CPU temperature \(value)"
        case .iconAndRPM:
            guard let rpm = state.fans.first?.currentRPM else { return "CoolMyMac, fan speed unavailable" }
            return "CoolMyMac, fan speed \(rpm) RPM"
        }
    }

    /// Continuous green→red gradient across 60–90°C using hue interpolation.
    private var thermalColor: Color {
        let temp = state.hottestTemp
        let normalizedTemp = max(0, min(1, (temp - Self.minTemp) / (Self.maxTemp - Self.minTemp)))
        // Hue: 0.33 = green, 0.0 = red. Shift linearly.
        let hue = 0.33 * (1.0 - normalizedTemp)
        // Ensure high contrast: darker in light mode, brighter in dark mode
        let brightness = colorScheme == .dark ? 0.95 : 0.65
        let saturation = colorScheme == .dark ? 0.85 : 1.0
        return Color(hue: hue, saturation: saturation, brightness: brightness)
    }
}
