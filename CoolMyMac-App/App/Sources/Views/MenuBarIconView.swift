// MenuBarIconView.swift
// The icon shown in the menu bar — supports icon-only, +temp, +RPM, and dynamic color.

import AppKit
import SwiftUI
import SMCKit

@MainActor
final class MenuBarIconCache {
    static let shared = MenuBarIconCache()

    struct Key: Equatable {
        let mode: IconDisplayMode
        let isVertical: Bool
        let dynamicColor: Bool
        let roundedTemp: Int
        let readingText: String
        let readingAnchor: String
        let isDark: Bool
    }

    private var cachedKey: Key?
    private var cachedImage: NSImage?

    func image(for key: Key, render: () -> NSImage) -> NSImage {
        if let cachedKey, cachedKey == key, let cachedImage {
            return cachedImage
        }
        let image = render()
        self.cachedKey = key
        self.cachedImage = image
        return image
    }
}

struct MenuBarIconView: View {

    var state: AppState
    @AppStorage("decimalResolution") private var decimalResolution: Int = 0
    @Environment(\.colorScheme) private var colorScheme

    private static let minTemp = 60.0
    private static let maxTemp = 90.0

    private var usesVerticalLayout: Bool {
        state.menuBarItemLayout == .vertical && state.iconDisplayMode != .iconOnly
    }

    var body: some View {
        Image(nsImage: renderedImage)
            .renderingMode(.original)
            .accessibilityLabel(Text(accessibilityLabel))
    }

    private var currentReadingValue: String {
        switch state.iconDisplayMode {
        case .iconOnly:
            return ""
        case .iconAndTemp:
            return state.cpuTemp.map { String(format: temperatureFormat, $0) } ?? ""
        case .iconAndRPM:
            return state.fans.first.map { "\($0.currentRPM)" } ?? ""
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

    private var readingAnchor: String {
        switch state.iconDisplayMode {
        case .iconOnly:
            return ""
        case .iconAndTemp:
            return temperatureAnchor
        case .iconAndRPM:
            return "9999"
        }
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

    private var renderedImage: NSImage {
        let isDark = colorScheme == .dark
        let roundedTemp = Int(state.hottestTemp.rounded())
        let key = MenuBarIconCache.Key(
            mode: state.iconDisplayMode,
            isVertical: usesVerticalLayout,
            dynamicColor: state.dynamicIconEnabled,
            roundedTemp: roundedTemp,
            readingText: currentReadingValue,
            readingAnchor: readingAnchor,
            isDark: isDark
        )

        return MenuBarIconCache.shared.image(for: key) {
            drawMenuBarIcon(
                mode: state.iconDisplayMode,
                isVertical: usesVerticalLayout,
                dynamicColor: state.dynamicIconEnabled,
                hottestTemp: state.hottestTemp,
                readingText: currentReadingValue,
                readingAnchor: readingAnchor,
                isDark: isDark
            )
        }
    }

    private func drawMenuBarIcon(
        mode: IconDisplayMode,
        isVertical: Bool,
        dynamicColor: Bool,
        hottestTemp: Double,
        readingText: String,
        readingAnchor: String,
        isDark: Bool
    ) -> NSImage {
        let norm = max(0, min(1, (hottestTemp - Self.minTemp) / (Self.maxTemp - Self.minTemp)))
        let hue = 0.33 * (1.0 - norm)
        let brightness = isDark ? 0.95 : 0.65
        let saturation = isDark ? 0.85 : 1.0
        let thermalNSColor = NSColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1.0)

        let symSize: CGFloat = isVertical ? 11 : 14
        let symConfig: NSImage.SymbolConfiguration
        if dynamicColor {
            symConfig = NSImage.SymbolConfiguration(pointSize: symSize, weight: .medium)
                .applying(NSImage.SymbolConfiguration(paletteColors: [thermalNSColor, thermalNSColor.withAlphaComponent(0.6)]))
        } else {
            symConfig = NSImage.SymbolConfiguration(pointSize: symSize, weight: .medium)
        }

        guard let symbol = NSImage(systemSymbolName: "wind", accessibilityDescription: nil)?.withSymbolConfiguration(symConfig) else {
            return NSImage()
        }

        if mode == .iconOnly {
            if !dynamicColor {
                symbol.isTemplate = true
            }
            return symbol
        }

        let fontSize: CGFloat = isVertical ? 9 : 12
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .medium)
        let textColor = NSColor.labelColor
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]

        let textSize = (readingText as NSString).size(withAttributes: attrs)
        let anchorSize = (readingAnchor as NSString).size(withAttributes: attrs)
        let colWidth = max(anchorSize.width, textSize.width)

        let totalHeight: CGFloat = 22.0
        let totalWidth: CGFloat

        if isVertical {
            totalWidth = ceil(max(symbol.size.width, colWidth))
            let img = NSImage(size: NSSize(width: totalWidth, height: totalHeight), flipped: false) { _ in
                let symX = (totalWidth - symbol.size.width) / 2.0
                let symY = totalHeight - symbol.size.height + 1.0
                symbol.draw(in: NSRect(x: symX, y: symY, width: symbol.size.width, height: symbol.size.height))

                let textX = (totalWidth - textSize.width) / 2.0
                let textY: CGFloat = 1.0
                (readingText as NSString).draw(at: NSPoint(x: textX, y: textY), withAttributes: attrs)
                return true
            }
            img.isTemplate = false
            return img
        } else {
            let spacing: CGFloat = 3.0
            totalWidth = ceil(symbol.size.width + spacing + colWidth)
            let img = NSImage(size: NSSize(width: totalWidth, height: totalHeight), flipped: false) { _ in
                let symY = (totalHeight - symbol.size.height) / 2.0
                symbol.draw(in: NSRect(x: 0, y: symY, width: symbol.size.width, height: symbol.size.height))

                let textX = symbol.size.width + spacing + (colWidth - textSize.width) / 2.0
                let textY = (totalHeight - textSize.height) / 2.0
                (readingText as NSString).draw(at: NSPoint(x: textX, y: textY), withAttributes: attrs)
                return true
            }
            img.isTemplate = false
            return img
        }
    }
}
