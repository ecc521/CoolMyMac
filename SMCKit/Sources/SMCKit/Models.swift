// Models.swift
// Public data models shared across all targets via SMCKit.
// All models conform to Codable for JSON-based XPC transport.

import Foundation

// MARK: - Sensor Reading

public enum SensorUnit: String, Codable, Sendable {
    case celsius = "°C"
    case watts = "W"
    case megahertz = "MHz"
}

/// A reading from a single sensor or metric.
public struct SensorReading: Codable, Identifiable, Sendable {
    public var id: String { name }
    public let name: String        // Human-readable name
    public let group: SensorGroup  // Which group this sensor belongs to
    public let value: Double       // Current reading value
    public let unit: SensorUnit    // Unit of measurement

    public init(name: String, group: SensorGroup, value: Double, unit: SensorUnit = .celsius) {
        self.name = name
        self.group = group
        self.value = value
        self.unit = unit
    }
}

/// Logical grouping of sensors.
public enum SensorGroup: String, Codable, CaseIterable, Sendable {
    case cpuCore = "CPU Core"
    case gpu = "GPU"
    case nand = "NAND (Storage)"
    case battery = "Battery"
    case enclosure = "Enclosure / Skin"
    case vrm = "VRM / Power"
    case wireless = "Wireless"
    case power = "Package Power"
    case clockSpeed = "Clock Speed"
    case other = "Other"
    
    public init?(rawValue: String) {
        switch rawValue {
        case "CPU Core", "CPU_CORES": self = .cpuCore
        case "GPU": self = .gpu
        case "NAND (Storage)", "NAND": self = .nand
        case "Battery": self = .battery
        case "Enclosure / Skin": self = .enclosure
        case "VRM / Power": self = .vrm
        case "Wireless": self = .wireless
        case "Package Power": self = .power
        case "Clock Speed": self = .clockSpeed
        case "Other", "OTHER": self = .other
        default: return nil
        }
    }
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

    /// Validates that the profile is structurally sound and mathematically safe to execute.
    /// Throws an error if any values are corrupted, out of bounds, or potentially dangerous.
    public func validate() throws {
        // Validate ID format (must be alphanumeric/hyphens/underscores, max 64 chars)
        guard !id.isEmpty, id.count <= 64 else {
            throw NSError(domain: "FanProfileError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Profile ID is invalid or too long."])
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard id.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw NSError(domain: "FanProfileError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Profile ID contains invalid characters."])
        }

        // Validate Settings
        guard settings.spinUpTime >= 0 && settings.spinDownTime >= 0 else {
            throw NSError(domain: "FanProfileError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Spin times cannot be negative."])
        }

        // Validate Curve
        if !isBuiltIn {
            guard !curve.points.isEmpty else {
                throw NSError(domain: "FanProfileError", code: 7, userInfo: [NSLocalizedDescriptionKey: "A custom profile must have at least one curve point."])
            }
        }
        
        var seenTemps = Set<Double>()
        for point in curve.points {
            guard point.value.isFinite && point.rpmPercentage.isFinite else {
                throw NSError(domain: "FanProfileError", code: 4, userInfo: [NSLocalizedDescriptionKey: "Curve points must be finite numbers."])
            }
            guard point.rpmPercentage >= 0.0 && point.rpmPercentage <= 1.0 else {
                throw NSError(domain: "FanProfileError", code: 5, userInfo: [NSLocalizedDescriptionKey: "RPM percentage must be between 0.0 and 1.0."])
            }
            guard !seenTemps.contains(point.value) else {
                throw NSError(domain: "FanProfileError", code: 6, userInfo: [NSLocalizedDescriptionKey: "Curve points must have unique temperatures. Remove the duplicate point at \(Int(point.value))°C."])
            }
            seenTemps.insert(point.value)
        }
    }
}

/// Piecewise linear temp→RPM curve.
/// Points must be sorted by temperature ascending.
public struct FanCurve: Codable, Sendable {
    /// Each breakpoint: (celsius, targetMinRPM)
    public let points: [CurvePoint]

    public init(points: [CurvePoint]) {
        // Filter out NaN/Infinite values and sort
        self.points = points
            .filter { $0.value.isFinite && $0.rpmPercentage.isFinite }
            .sorted { $0.value < $1.value }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawPoints = try container.decode([CurvePoint].self, forKey: .points)
        // Ensure points are sorted and finite even when decoded from raw JSON
        self.points = rawPoints
            .filter { $0.value.isFinite && $0.rpmPercentage.isFinite }
            .sorted { $0.value < $1.value }
    }

    /// Interpolates the target RPM percentage for a given temperature.
    /// Returns a value between 0.0 and 1.0.
    public func targetPercentage(for value: Double) -> Double {
        guard !points.isEmpty else { return 0.0 }
        if value <= points.first!.value { return points.first!.rpmPercentage }
        if value >= points.last!.value  { return points.last!.rpmPercentage  }

        for i in 0..<(points.count - 1) {
            let lo = points[i], hi = points[i + 1]
            if value >= lo.value && value <= hi.value {
                let tempRange = hi.value - lo.value
                if tempRange <= 0.001 { return hi.rpmPercentage } // Prevent divide by zero (NaN)
                
                let t = (value - lo.value) / tempRange
                return lo.rpmPercentage + t * (hi.rpmPercentage - lo.rpmPercentage)
            }
        }
        return points.last!.rpmPercentage
    }
}

public struct CurvePoint: Codable, Sendable {
    public let value: Double
    public let rpmPercentage: Double

    public init(value: Double, rpmPercentage: Double) {
        self.value = value
        self.rpmPercentage = max(0.0, min(1.0, rpmPercentage))
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.value = try container.decode(Double.self, forKey: .value)
        let rawRpm = try container.decode(Double.self, forKey: .rpmPercentage)
        self.rpmPercentage = max(0.0, min(1.0, rawRpm))
    }
}

/// Aggregation and smoothing settings for a profile.
public struct ProfileSettings: Codable, Sendable {
    /// Which sensor groups drive the fan curve.
    public let sources: [SensorGroup]
    /// Specific sensors to exclude from the aggregation.
    public let excludedSensors: [String]
    /// How to reduce multiple sensor readings to one driving temperature.
    public let aggregation: AggregationMode
    public let spinUpTime: Double
    public let spinDownTime: Double

    public init(
        sources: [SensorGroup] = [.cpuCore, .gpu],
        excludedSensors: [String] = [],
        aggregation: AggregationMode = .max,
        spinUpTime: Double = 3.0,
        spinDownTime: Double = 10.0
    ) {
        self.sources = sources
        self.excludedSensors = excludedSensors
        self.aggregation = aggregation
        self.spinUpTime = spinUpTime
        self.spinDownTime = spinDownTime
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.sources = try container.decodeIfPresent([SensorGroup].self, forKey: .sources) ?? [.cpuCore, .gpu]
        self.excludedSensors = try container.decodeIfPresent([String].self, forKey: .excludedSensors) ?? []
        self.aggregation = try container.decodeIfPresent(AggregationMode.self, forKey: .aggregation) ?? .max
        
        // Backwards compatibility for older JSON profiles
        if let oldSmoothing = try? container.decodeIfPresent(Double.self, forKey: CodingKeys(stringValue: "smoothingWindowSeconds")!) {
            self.spinUpTime = 0.0
            self.spinDownTime = oldSmoothing
        } else {
            self.spinUpTime = try container.decodeIfPresent(Double.self, forKey: .spinUpTime) ?? 0.0
            self.spinDownTime = try container.decodeIfPresent(Double.self, forKey: .spinDownTime) ?? 5.0
        }
    }

    private enum CodingKeys: String, CodingKey {
        case sources, excludedSensors, aggregation, spinUpTime, spinDownTime
        case smoothingWindowSeconds // For backwards compatibility during decoding
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sources, forKey: .sources)
        try container.encode(excludedSensors, forKey: .excludedSensors)
        try container.encode(aggregation, forKey: .aggregation)
        try container.encode(spinUpTime, forKey: .spinUpTime)
        try container.encode(spinDownTime, forKey: .spinDownTime)
    }
}

public enum AggregationMode: String, Codable, Sendable {
    case max     = "MAX"
    case average = "AVERAGE"
}
