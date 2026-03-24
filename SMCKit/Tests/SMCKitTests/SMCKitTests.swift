// SMCKitTests.swift
// Unit tests for SMCKit models and logic that can run without real hardware.

import XCTest
@testable import SMCKit

final class SMCKitTests: XCTestCase {

    // MARK: - FanCurve Interpolation

    func testFanCurveInterpolation_belowMinPoint() {
        let curve = FanCurve(points: [
            CurvePoint(celsius: 40, rpmPercentage: 0.2),
            CurvePoint(celsius: 80, rpmPercentage: 1.0),
        ])
        XCTAssertEqual(curve.targetPercentage(for: 20), 0.2, "Below min temp should return min %")
    }

    func testFanCurveInterpolation_aboveMaxPoint() {
        let curve = FanCurve(points: [
            CurvePoint(celsius: 40, rpmPercentage: 0.2),
            CurvePoint(celsius: 80, rpmPercentage: 1.0),
        ])
        XCTAssertEqual(curve.targetPercentage(for: 100), 1.0, "Above max temp should return max %")
    }

    func testFanCurveInterpolation_midpoint() {
        let curve = FanCurve(points: [
            CurvePoint(celsius: 40, rpmPercentage: 0.2),
            CurvePoint(celsius: 80, rpmPercentage: 1.0),
        ])
        // At midpoint (60°C), should be exactly 50% between 0.2 and 1.0 = 0.6
        XCTAssertEqual(curve.targetPercentage(for: 60), 0.6, accuracy: 0.001, "Midpoint should interpolate linearly")
    }

    func testFanCurveInterpolation_exactPoint() {
        let curve = FanCurve(points: [
            CurvePoint(celsius: 55, rpmPercentage: 0.3),
            CurvePoint(celsius: 75, rpmPercentage: 0.7),
        ])
        XCTAssertEqual(curve.targetPercentage(for: 55), 0.3, "Exact match should return exact %")
        XCTAssertEqual(curve.targetPercentage(for: 75), 0.7, "Exact match should return exact %")
    }

    func testFanCurveInterpolation_unsortedPoints() {
        // Points passed out of order should still produce correct results after sorting
        let curve = FanCurve(points: [
            CurvePoint(celsius: 80, rpmPercentage: 1.0),
            CurvePoint(celsius: 40, rpmPercentage: 0.2),
        ])
        XCTAssertEqual(curve.targetPercentage(for: 60), 0.6, accuracy: 0.001, "Unsorted points should be handled correctly")
    }

    func testFanCurveInterpolation_emptyPoints() {
        let curve = FanCurve(points: [])
        XCTAssertEqual(curve.targetPercentage(for: 70), 0.0, "Empty curve (Auto mode) should return 0.0")
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
        XCTAssertEqual(maxProfile.curve.targetPercentage(for: 0),   1.0)
        XCTAssertEqual(maxProfile.curve.targetPercentage(for: 50),  1.0)
        XCTAssertEqual(maxProfile.curve.targetPercentage(for: 100), 1.0)
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
