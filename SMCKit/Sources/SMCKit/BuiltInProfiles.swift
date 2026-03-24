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
            CurvePoint(celsius: 40, rpmPercentage: 0.0),   // ~Idle / Floor
            CurvePoint(celsius: 55, rpmPercentage: 0.06),  // ~1500 RPM equivalent
            CurvePoint(celsius: 65, rpmPercentage: 0.16),  // ~2000 RPM equivalent
            CurvePoint(celsius: 75, rpmPercentage: 0.38),  // ~3000 RPM equivalent
            CurvePoint(celsius: 85, rpmPercentage: 0.69),  // ~4500 RPM equivalent
            CurvePoint(celsius: 95, rpmPercentage: 1.0),   // Max
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
            CurvePoint(celsius: 40, rpmPercentage: 0.16),  // Higher idle floor (~2000 RPM)
            CurvePoint(celsius: 55, rpmPercentage: 0.27),  // Light load (~2500 RPM)
            CurvePoint(celsius: 65, rpmPercentage: 0.48),  // Moderate load (~3500 RPM)
            CurvePoint(celsius: 75, rpmPercentage: 0.69),  // Heavy load (~4500 RPM)
            CurvePoint(celsius: 85, rpmPercentage: 1.0),   // Aggressive ceiling — max at 85°C
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
            CurvePoint(celsius: 0,   rpmPercentage: 1.0),  // Always max
            CurvePoint(celsius: 100, rpmPercentage: 1.0),
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
