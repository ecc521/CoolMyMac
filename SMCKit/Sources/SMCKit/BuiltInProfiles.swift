// BuiltInProfiles.swift
// Defines the four built-in fan profiles: Auto, Balanced, Performance, Max.

import Foundation

public extension FanProfile {

    // MARK: - Auto

    /// Auto mode: no override. Apple's thermal management stays in full control.
    static let auto = FanProfile(
        id: "auto",
        displayName: "Auto",
        isBuiltIn: true,
        curve: FanCurve(points: []),  // No points = no control
        settings: ProfileSettings(
            sources: [.cpuCore, .gpu],
            aggregation: .max,
            smoothingWindowSeconds: 5.0
        )
    )

    // MARK: - Balanced (Default)

    /// Balanced: Apple's minimum floor with a more aggressive ceiling.
    /// Fans ramp up earlier and harder than Apple defaults.
    static let balanced = FanProfile(
        id: "balanced",
        displayName: "Balanced",
        isBuiltIn: true,
        curve: FanCurve(points: [
            CurvePoint(celsius: 40, rpm: 1200),  // Idle — match Apple's floor
            CurvePoint(celsius: 55, rpm: 1500),  // Light load
            CurvePoint(celsius: 65, rpm: 2000),  // Moderate load
            CurvePoint(celsius: 75, rpm: 3000),  // Heavy load
            CurvePoint(celsius: 85, rpm: 4500),  // Thermal stress
            CurvePoint(celsius: 95, rpm: 6000),  // Max — emergency ceiling
        ]),
        settings: ProfileSettings(
            sources: [.cpuCore, .gpu],
            aggregation: .max,
            smoothingWindowSeconds: 5.0
        )
    )

    // MARK: - Performance

    /// Performance: Higher minimums, aggressive ramp — prioritizes thermals over acoustics.
    static let performance = FanProfile(
        id: "performance",
        displayName: "Performance",
        isBuiltIn: true,
        curve: FanCurve(points: [
            CurvePoint(celsius: 40, rpm: 2000),  // Higher idle floor
            CurvePoint(celsius: 55, rpm: 2500),  // Light load
            CurvePoint(celsius: 65, rpm: 3500),  // Moderate load
            CurvePoint(celsius: 75, rpm: 4500),  // Heavy load
            CurvePoint(celsius: 85, rpm: 6000),  // Aggressive ceiling — max at 85°C
        ]),
        settings: ProfileSettings(
            sources: [.cpuCore, .gpu],
            aggregation: .max,
            smoothingWindowSeconds: 3.0  // Faster response time
        )
    )

    // MARK: - Max

    /// Max: Fans always at maximum RPM. No curve — constant maximum.
    static let max = FanProfile(
        id: "max",
        displayName: "Max",
        isBuiltIn: true,
        curve: FanCurve(points: [
            CurvePoint(celsius: 0,   rpm: 6000),  // Always max
            CurvePoint(celsius: 100, rpm: 6000),
        ]),
        settings: ProfileSettings(
            sources: [.cpuCore, .gpu],
            aggregation: .max,
            smoothingWindowSeconds: 1.0
        )
    )

    // MARK: - All Built-ins

    static let allBuiltIn: [FanProfile] = [.auto, .balanced, .performance, .max]
}
