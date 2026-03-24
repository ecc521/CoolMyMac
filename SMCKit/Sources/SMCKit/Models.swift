// Models.swift
// Public data models shared across all targets via SMCKit.
// All models conform to Codable for JSON-based XPC transport.

import Foundation

// MARK: - Sensor Reading

/// A temperature reading from a single SMC sensor.
public struct SensorReading: Codable, Identifiable, Sendable {
    public let id: String          // SMC key, e.g. "TC0C"
    public let name: String        // Human-readable name, e.g. "CPU Core 0"
    public let group: SensorGroup  // Which group this sensor belongs to
    public let celsius: Double     // Current reading in °C

    public init(id: String, name: String, group: SensorGroup, celsius: Double) {
        self.id = id
        self.name = name
        self.group = group
        self.celsius = celsius
    }
}

/// Logical grouping of sensors for fan curve aggregation.
public enum SensorGroup: String, Codable, CaseIterable, Sendable {
    case cpuCore = "CPU_CORES"
    case gpu     = "GPU"
    case nand    = "NAND"
    case other   = "OTHER"
}

// MARK: - Fan Status

/// Current state of a single physical fan.
public struct FanStatus: Codable, Identifiable, Sendable {
    public let id: Int             // Fan index (0-based)
    public let name: String        // e.g. "Left Fan", "Right Fan", "Fan 0"
    public let currentRPM: Int     // Actual RPM from SMC
    public let minRPM: Int         // Current programmatic minimum RPM
    public let maxRPM: Int         // Hardware maximum RPM
    public let isManaged: Bool     // true if CoolMyMac is controlling this fan

    public init(id: Int, name: String, currentRPM: Int, minRPM: Int, maxRPM: Int, isManaged: Bool) {
        self.id = id
        self.name = name
        self.currentRPM = currentRPM
        self.minRPM = minRPM
        self.maxRPM = maxRPM
        self.isManaged = isManaged
    }
}

// MARK: - Fan Profile

/// A complete fan control profile, including curve and aggregation settings.
public struct FanProfile: Codable, Identifiable, Sendable {
    public let id: String              // Unique name, e.g. "balanced", "Dev Mode"
    public let displayName: String     // User-facing label
    public let isBuiltIn: Bool         // true for Auto/Balanced/Performance/Max
    public let curve: FanCurve         // The thermal curve definition
    public let settings: ProfileSettings

    public init(
        id: String,
        displayName: String,
        isBuiltIn: Bool,
        curve: FanCurve,
        settings: ProfileSettings
    ) {
        self.id = id
        self.displayName = displayName
        self.isBuiltIn = isBuiltIn
        self.curve = curve
        self.settings = settings
    }
}

/// Piecewise linear temp→RPM curve.
/// Points must be sorted by temperature ascending.
public struct FanCurve: Codable, Sendable {
    /// Each breakpoint: (celsius, targetMinRPM)
    public let points: [CurvePoint]

    public init(points: [CurvePoint]) {
        self.points = points.sorted { $0.celsius < $1.celsius }
    }

    /// Interpolates the target RPM percentage for a given temperature.
    /// Returns a value between 0.0 and 1.0.
    public func targetPercentage(for celsius: Double) -> Double {
        guard !points.isEmpty else { return 0.0 }
        if celsius <= points.first!.celsius { return points.first!.rpmPercentage }
        if celsius >= points.last!.celsius  { return points.last!.rpmPercentage  }

        for i in 0..<(points.count - 1) {
            let lo = points[i], hi = points[i + 1]
            if celsius >= lo.celsius && celsius <= hi.celsius {
                let t = (celsius - lo.celsius) / (hi.celsius - lo.celsius)
                return lo.rpmPercentage + t * (hi.rpmPercentage - lo.rpmPercentage)
            }
        }
        return points.last!.rpmPercentage
    }
}

public struct CurvePoint: Codable, Sendable {
    public let celsius: Double
    public let rpmPercentage: Double

    public init(celsius: Double, rpmPercentage: Double) {
        self.celsius = celsius
        self.rpmPercentage = max(0.0, min(1.0, rpmPercentage))
    }
}

/// Aggregation and smoothing settings for a profile.
public struct ProfileSettings: Codable, Sendable {
    /// Which sensor groups drive the fan curve.
    public let sources: [SensorGroup]
    /// How to reduce multiple sensor readings to one driving temperature.
    public let aggregation: AggregationMode
    /// Rolling-average window in seconds to prevent RPM hunting.
    public let smoothingWindowSeconds: Double

    public init(
        sources: [SensorGroup] = [.cpuCore, .gpu],
        aggregation: AggregationMode = .max,
        smoothingWindowSeconds: Double = 5.0
    ) {
        self.sources = sources
        self.aggregation = aggregation
        self.smoothingWindowSeconds = smoothingWindowSeconds
    }
}

public enum AggregationMode: String, Codable, Sendable {
    case max     = "MAX"
    case average = "AVERAGE"
}
