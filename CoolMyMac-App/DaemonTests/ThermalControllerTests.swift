// ThermalControllerTests.swift
// Tests the daemon's thermal polling and fan curve application logic
// using a mocked SMC backend.

import XCTest
import SMCKit
// @testable import Daemon // (Assuming Daemon is the target name; if it's an executable we might have to compile the source file into the test target directly)
// We'll compile ThermalController directly into the test target to avoid executable import issues.

final class ThermalControllerTests: XCTestCase {

    var mockProvider: MockSMCProvider!
    var controller: SMCController!

    override func setUpWithError() throws {
        mockProvider = MockSMCProvider()
        
        // Setup mock hardware: 1 fan (min: 1200, max: 6000), 1 CPU temp sensor
        mockProvider.mockedFans = [
            FanStatus(id: 0, name: "Left Fan", currentRPM: 1200, minRPM: 1200, maxRPM: 6000, isManaged: false)
        ]
        mockProvider.mockedSensors = [
            SensorReading(id: "TC0C", name: "CPU Core", group: .cpuCore, celsius: 40.0)
        ]

        controller = SMCController(provider: mockProvider)
        ThermalController.shared.inject(controller: controller)
    }

    override func tearDownWithError() throws {
        ThermalController.shared.stop()
        ThermalController.shared.inject(controller: nil)
    }

    func testAutoProfile_LeavesFansUnmanaged() throws {
        // Given
        try ProfileStore.shared.setActiveProfile(id: "auto")
        
        // When
        ThermalController.shared.start()
        
        // Let it poll once (timer fires immediately, but we might need a small delay)
        let exp = expectation(description: "Poll")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)
        
        // Then
        XCTAssertTrue(mockProvider.setFanMinRPMLog.isEmpty, "Auto mode should never write to SMC fans")
        
        let fans = ThermalController.shared.latestFanStatus
        XCTAssertFalse(fans.first?.isManaged ?? true, "Fans should not be marked managed in Auto mode")
    }

    func testMaxProfile_DrivesFansToMaxRPM() throws {
        // Given
        try ProfileStore.shared.setActiveProfile(id: "max")
        
        // When
        ThermalController.shared.start()
        
        let exp = expectation(description: "Poll")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)
        
        // Then
        XCTAssertFalse(mockProvider.setFanMinRPMLog.isEmpty, "Max mode should write to SMC fans")
        if let lastWrite = mockProvider.setFanMinRPMLog.last {
            XCTAssertEqual(lastWrite.index, 0)
            XCTAssertEqual(lastWrite.rpm, 6000, "Max profile should drive fan to its hardware maxRPM (6000)")
        } else {
            XCTFail("No fan write occurred")
        }
    }
}
