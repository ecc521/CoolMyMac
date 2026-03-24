// SMCKitTests.swift
// Unit tests for SMCKit models and logic that can run without real hardware.

import XCTest
@testable import SMCKit

final class SMCKitTests: XCTestCase {

    // MARK: - FanCurve Interpolation

    func testFanCurveInterpolation_belowMinPoint() {
        let curve = FanCurve(points: [
            CurvePoint(celsius: 40, rpm: 1200),
            CurvePoint(celsius: 80, rpm: 6000),
        ])
        XCTAssertEqual(curve.targetRPM(for: 20), 1200, "Below min temp should return min RPM")
    }

    func testFanCurveInterpolation_aboveMaxPoint() {
        let curve = FanCurve(points: [
            CurvePoint(celsius: 40, rpm: 1200),
            CurvePoint(celsius: 80, rpm: 6000),
        ])
        XCTAssertEqual(curve.targetRPM(for: 100), 6000, "Above max temp should return max RPM")
    }

    func testFanCurveInterpolation_midpoint() {
        let curve = FanCurve(points: [
            CurvePoint(celsius: 40, rpm: 1000),
            CurvePoint(celsius: 80, rpm: 5000),
        ])
        // At midpoint (60°C), should be exactly 50% between 1000 and 5000 = 3000
        XCTAssertEqual(curve.targetRPM(for: 60), 3000, "Midpoint should interpolate linearly")
    }

    func testFanCurveInterpolation_exactPoint() {
        let curve = FanCurve(points: [
            CurvePoint(celsius: 55, rpm: 2000),
            CurvePoint(celsius: 75, rpm: 4000),
        ])
        XCTAssertEqual(curve.targetRPM(for: 55), 2000, "Exact match should return exact RPM")
        XCTAssertEqual(curve.targetRPM(for: 75), 4000, "Exact match should return exact RPM")
    }

    func testFanCurveInterpolation_unsortedPoints() {
        // Points passed out of order should still produce correct results after sorting
        let curve = FanCurve(points: [
            CurvePoint(celsius: 80, rpm: 6000),
            CurvePoint(celsius: 40, rpm: 1000),
        ])
        XCTAssertEqual(curve.targetRPM(for: 60), 3500, "Unsorted points should be handled correctly")
    }

    func testFanCurveInterpolation_emptyPoints() {
        let curve = FanCurve(points: [])
        XCTAssertEqual(curve.targetRPM(for: 70), 0, "Empty curve (Auto mode) should return 0")
    }

    // MARK: - Built-in Profiles

    func testBuiltInProfilesAreAllPresent() {
        XCTAssertEqual(FanProfile.allBuiltIn.count, 4)
        let ids = FanProfile.allBuiltIn.map(\.id)
        XCTAssertTrue(ids.contains("auto"))
        XCTAssertTrue(ids.contains("balanced"))
        XCTAssertTrue(ids.contains("performance"))
        XCTAssertTrue(ids.contains("max"))
    }

    func testAutoProfileHasNoControlPoints() {
        XCTAssertTrue(FanProfile.auto.curve.points.isEmpty, "Auto should have no curve points — Apple stays in control")
    }

    func testMaxProfileAlwaysReturnsMaxRPM() {
        let maxProfile = FanProfile.max
        XCTAssertEqual(maxProfile.curve.targetRPM(for: 0),   6000)
        XCTAssertEqual(maxProfile.curve.targetRPM(for: 50),  6000)
        XCTAssertEqual(maxProfile.curve.targetRPM(for: 100), 6000)
    }

    func testBuiltInProfilesAreBuiltIn() {
        for profile in FanProfile.allBuiltIn {
            XCTAssertTrue(profile.isBuiltIn, "\(profile.id) should be marked as built-in")
        }
    }

    // MARK: - Codable Round-trip

    func testFanProfileCodableRoundTrip() throws {
        let profile = FanProfile.balanced
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(FanProfile.self, from: data)
        XCTAssertEqual(decoded.id, profile.id)
        XCTAssertEqual(decoded.displayName, profile.displayName)
        XCTAssertEqual(decoded.curve.points.count, profile.curve.points.count)
    }

    func testSensorReadingCodableRoundTrip() throws {
        let reading = SensorReading(id: "TC0C", name: "CPU Core 0", group: .cpuCore, celsius: 72.5)
        let data = try JSONEncoder().encode(reading)
        let decoded = try JSONDecoder().decode(SensorReading.self, from: data)
        XCTAssertEqual(decoded.id, "TC0C")
        XCTAssertEqual(decoded.celsius, 72.5)
        XCTAssertEqual(decoded.group, .cpuCore)
    }

    // MARK: - AggregationMode

    func testAggregationModeCodable() throws {
        let settings = ProfileSettings(sources: [.cpuCore, .gpu], aggregation: .max, smoothingWindowSeconds: 5.0)
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(ProfileSettings.self, from: data)
        XCTAssertEqual(decoded.aggregation, .max)
        XCTAssertEqual(decoded.smoothingWindowSeconds, 5.0)
    }
}
