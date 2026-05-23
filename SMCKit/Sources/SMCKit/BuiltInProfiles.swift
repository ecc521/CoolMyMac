// BuiltInProfiles.swift
// Defines the four built-in fan profiles: Auto, Balanced, Performance, Max.

import Foundation

public extension FanProfile {

    // MARK: - System

    /// System mode: no override. Apple's thermal management stays in full control.
    static let system = FanProfile(
        id: "system",
        displayName: "System",
        isBuiltIn: true,
        curve: FanCurve(points: []),  // No points = no control
        settings: ProfileSettings(
            sources: [.cpuCore, .gpu],
            aggregation: .max,
            spinUpTime: 0.0,
            spinDownTime: 5.0
        )
    )

    // MARK: - Balanced (Default)

    /// Balanced: Apple's minimum floor with a more aggressive ceiling.
    /// Fans ramp up earlier and harder than Apple defaults.
    static let balanced = FanProfile(
        id: "balanced",
        displayName: "Balanced",
        isBuiltIn: false,
        curve: FanCurve(points: [
            CurvePoint(value: 40, rpmPercentage: 0.0),   // ~Idle / Floor
            CurvePoint(value: 55, rpmPercentage: 0.06),  // ~1500 RPM equivalent
            CurvePoint(value: 65, rpmPercentage: 0.16),  // ~2000 RPM equivalent
            CurvePoint(value: 75, rpmPercentage: 0.38),  // ~3000 RPM equivalent
            CurvePoint(value: 85, rpmPercentage: 0.69),  // ~4500 RPM equivalent
            CurvePoint(value: 95, rpmPercentage: 1.0),   // Max
        ]),
        settings: ProfileSettings(
            sources: [.cpuCore, .gpu],
            aggregation: .max,
            spinUpTime: 5.0,
            spinDownTime: 10.0
        )
    )

    // MARK: - Performance

    /// Performance: Higher minimums, aggressive ramp — prioritizes thermals over acoustics.
    static let performance = FanProfile(
        id: "performance",
        displayName: "Performance",
        isBuiltIn: false,
        curve: FanCurve(points: [
            CurvePoint(value: 40, rpmPercentage: 0.16),  // Higher idle floor (~2000 RPM)
            CurvePoint(value: 55, rpmPercentage: 0.27),  // Light load (~2500 RPM)
            CurvePoint(value: 65, rpmPercentage: 0.48),  // Moderate load (~3500 RPM)
            CurvePoint(value: 75, rpmPercentage: 0.69),  // Heavy load (~4500 RPM)
            CurvePoint(value: 85, rpmPercentage: 1.0),   // Aggressive ceiling — max at 85°C
        ]),
        settings: ProfileSettings(
            sources: [.cpuCore, .gpu],
            aggregation: .max,
            spinUpTime: 3.0,
            spinDownTime: 5.0
        )
    )

    // MARK: - Max

    /// Max: Runs all fans at 100% capacity continuously.
    static let max = FanProfile(
        id: "max",
        displayName: "Max",
        isBuiltIn: false,
        curve: FanCurve(points: [
            CurvePoint(value: 0,   rpmPercentage: 1.0),
            CurvePoint(value: 100, rpmPercentage: 1.0),
        ]),
        settings: ProfileSettings(
            sources: [.cpuCore, .gpu],
            aggregation: .max,
            spinUpTime: 0.0,
            spinDownTime: 0.0
        )
    )

    // MARK: - All
    static let allBuiltIn: [FanProfile] = [.system]
    
    // MARK: - Configurable Templates
    static let defaultTemplates: [FanProfile] = [.balanced, .performance, .max]
}
