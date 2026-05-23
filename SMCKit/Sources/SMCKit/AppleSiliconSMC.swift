// AppleSiliconSMC.swift
// Apple Silicon SMC backend using IOKit.
// Uses AppleSMC service but focuses on modern keys (Ftst, F0Tg) and data types (ui8, fpe2).

import Foundation
import IOKit

// MARK: - IOKit Structs

private let kIOACPIClassName = "AppleSMC"

private struct SMCKeyData_vers_t {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMCKeyData_pLimitData_t {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

private struct SMCKeyData_keyInfo_t {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

private struct SMCKeyData_t {
    var key: UInt32 = 0
    var vers: SMCKeyData_vers_t = SMCKeyData_vers_t()
    var padding_vers: (UInt8, UInt8) = (0,0)
    var pLimitData: SMCKeyData_pLimitData_t = SMCKeyData_pLimitData_t()
    var keyInfo: SMCKeyData_keyInfo_t = SMCKeyData_keyInfo_t()
    var padding_keyInfo: (UInt8, UInt8, UInt8) = (0,0,0)
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var padding_data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (
        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    )
}

private struct SMCVal_t {
    var key: String = ""
    var dataSize: UInt32 = 0
    var dataType: String = ""
    var bytes: [UInt8] = Array(repeating: 0, count: 32)
}

private let KERNEL_INDEX_SMC = 2
private let SMC_CMD_READ_BYTES: UInt8 = 5
private let SMC_CMD_WRITE_BYTES: UInt8 = 6
private let SMC_CMD_READ_KEYINFO: UInt8 = 9

// MARK: - Helpers

private func toFourCC(_ string: String) -> UInt32 {
    var result: UInt32 = 0
    for char in string.utf8.prefix(4) {
        result = (result << 8) | UInt32(char)
    }
    return result
}

private func fromFourCC(_ value: UInt32) -> String {
    var chars: [Character] = []
    for i in stride(from: 24, through: 0, by: -8) {
        let byte = UInt8((value >> i) & 0xFF)
        chars.append(Character(UnicodeScalar(byte)))
    }
    return String(chars)
}

private func sp78ToDouble(_ bytes: [UInt8]) -> Double {
    guard bytes.count >= 2 else { return 0.0 }
    let raw = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
    return Double(raw) / 4.0
}

private func doubleToSP78(_ value: Double) -> [UInt8] {
    let raw = UInt16(value * 4.0)
    return [UInt8(raw >> 8), UInt8(raw & 0xFF)]
}

// MARK: - AppleSiliconSMC

final class AppleSiliconSMC: SMCProvider {

    private var connection: io_connect_t = 0

    init() throws {
        let service: io_service_t = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching(kIOACPIClassName)
        )

        guard service != 0 else {
            throw SMCError.deviceNotFound
        }

        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        IOObjectRelease(service)

        guard result == kIOReturnSuccess else {
            throw SMCError.deviceNotFound
        }
    }

    deinit {
        if connection != 0 {
            IOServiceClose(connection)
        }
    }

    // MARK: - Temperature via IOHIDEventSystem

    private var cachedThermalKeys: [(String, SensorGroup, String)]?

    func readTemperatures(for groups: Set<SensorGroup>? = nil) throws -> [SensorReading] {
        if cachedThermalKeys == nil {
            var discovered: [(String, SensorGroup, String)] = []
            
            var inputStruct  = SMCKeyData_t()
            var outputStruct = SMCKeyData_t()

            inputStruct.key = toFourCC("#KEY")
            inputStruct.data8 = SMC_CMD_READ_KEYINFO
            try? callSMC(&inputStruct, output: &outputStruct)

            inputStruct.keyInfo = outputStruct.keyInfo
            inputStruct.data8 = SMC_CMD_READ_BYTES
            try? callSMC(&inputStruct, output: &outputStruct)

            let count = Int((UInt32(outputStruct.bytes.0) << 24) |
                            (UInt32(outputStruct.bytes.1) << 16) |
                            (UInt32(outputStruct.bytes.2) << 8)  |
                            UInt32(outputStruct.bytes.3))

            for i in 0..<count {
                var iStruct = SMCKeyData_t()
                var oStruct = SMCKeyData_t()
                iStruct.data8 = 8 // READ_INDEX
                iStruct.data32 = UInt32(i)
                
                if (try? callSMC(&iStruct, output: &oStruct)) == nil { continue }
                
                let key = fromFourCC(oStruct.key)
                if !key.hasPrefix("T") { continue }
                
                var group: SensorGroup = .other
                var readableName = key
                
                if key.hasPrefix("Tp") {
                    group = .cpuCore
                    readableName = "CPU P-Core (\(key))"
                } else if key.hasPrefix("Te") {
                    group = .cpuCore
                    readableName = "CPU E-Core (\(key))"
                } else if key.hasPrefix("Tg") {
                    group = .gpu
                    readableName = "GPU (\(key))"
                } else if key.hasPrefix("TN") {
                    group = .nand
                    readableName = "Storage (\(key))"
                } else if key.hasPrefix("Tb") {
                    group = .battery
                    readableName = "Battery (\(key))"
                } else if key.hasPrefix("Ts") || key.hasPrefix("Ta") {
                    group = .enclosure
                    readableName = "Enclosure (\(key))"
                } else if key.hasPrefix("Tw") || key.hasPrefix("TW") {
                    group = .wireless
                    readableName = "Wireless (\(key))"
                } else if key.hasPrefix("Tv") || key.hasPrefix("TV") {
                    group = .vrm
                    readableName = "VRM / Power (\(key))"
                } else if key.hasPrefix("Tm") {
                    group = .other
                    readableName = "Memory (\(key))"
                } else {
                    readableName = "System (\(key))"
                }
                
                discovered.append((key, group, readableName))
            }
            cachedThermalKeys = discovered
        }

        var readings: [SensorReading] = []
        
        for (key, group, readableName) in cachedThermalKeys! {
            if let groups = groups, !groups.contains(group) {
                continue
            }
            
            guard let val = try? readKey(key) else { continue }
            
            var temp: Double = 0.0
            if val.dataType == "flt " && val.bytes.count >= 4 {
                var floatBits: UInt32 = 0
                floatBits |= UInt32(val.bytes[0])
                floatBits |= UInt32(val.bytes[1]) << 8
                floatBits |= UInt32(val.bytes[2]) << 16
                floatBits |= UInt32(val.bytes[3]) << 24
                temp = Double(Float(bitPattern: floatBits))
            } else if val.dataType == "sp78" && val.bytes.count >= 2 {
                temp = sp78ToDouble(val.bytes)
            }
            
            if temp > 0 && temp < 150 {
                readings.append(SensorReading(name: readableName, group: group, value: temp))
            }
        }
        
        return readings
    }

    // MARK: - Fan Control

    func fanCount() throws -> Int {
        let val = try readKey("FNum")
        guard val.bytes.count >= 1 else { return 0 }
        return Int(val.bytes[0])
    }

    func readFan(index: Int) throws -> FanStatus {
        let count = try fanCount()
        guard index < count else {
            throw SMCError.keyNotFound("Fan index \(index) out of range")
        }

        let actualRPM = Int(try readRPMKey("F\(index)Ac"))
        let minRPM = Int(try readRPMKey("F\(index)Mn"))
        let maxRPM = Int(try readRPMKey("F\(index)Mx"))

        let name = count == 1 ? "Fan" : (index == 0 ? "Left Fan" : "Right Fan")

        return FanStatus(
            id: index,
            name: name,
            currentRPM: actualRPM,
            minRPM: minRPM,
            maxRPM: maxRPM,
            isManaged: false
        )
    }

    func setFanMinRPM(index: Int, rpm: Int) throws {
        // On Apple Silicon, to override the fan, we must set F%dMd = 1
        try setManualMode(true)
        
        // Then we write the target RPM. F0Mn is often ignored.
        try writeRPMKey("F\(index)Tg", rpm: Double(rpm))
        
        // To only set the floor, the caller (LaunchDaemon) must be constantly 
        // comparing this `rpm` to Apple's `F0Ac` and only calling this if `rpm > F0Ac`.
        // If `rpm <= F0Ac`, it should call `resetFan()`.
    }

    func resetFan(index: Int) throws {
        // Relinquish control back to thermalmonitord
        try setManualMode(false)
    }

    private func setManualMode(_ manual: Bool) throws {
        let value: UInt8 = manual ? 1 : 0
        let bytes: [UInt8] = [value]
        
        let count = try fanCount()
        for i in 0..<count {
            // Write to F%dmd (Fan Mode: 0=Auto, 1=Manual) - note the lowercase 'md'
            do {
                try writeKey("F\(i)md", bytes: bytes, dataType: "ui8", dataSize: 1)
            } catch {
                // Ignore if specific fan mode key fails, try next
            }
        }
    }

    // MARK: - IOKit Private Helpers

    private func readRPMKey(_ key: String) throws -> Double {
        let val = try readKey(key)
        
        if val.dataType == "flt " && val.bytes.count >= 4 {
            var floatBits: UInt32 = 0
            floatBits |= UInt32(val.bytes[0])
            floatBits |= UInt32(val.bytes[1]) << 8
            floatBits |= UInt32(val.bytes[2]) << 16
            floatBits |= UInt32(val.bytes[3]) << 24
            let f = Float(bitPattern: floatBits)
            return Double(f)
        }
        
        let d = sp78ToDouble(val.bytes)
        return d.isNaN || d.isInfinite ? 0.0 : min(max(d, 0.0), 20000.0)
    }

    private func writeRPMKey(_ key: String, rpm: Double) throws {
        // Read key info first to determine type
        var inputStruct  = SMCKeyData_t()
        var outputStruct = SMCKeyData_t()
        inputStruct.key = toFourCC(key)
        inputStruct.data8 = SMC_CMD_READ_KEYINFO
        try callSMC(&inputStruct, output: &outputStruct)
        
        let dataType = fromFourCC(outputStruct.keyInfo.dataType).trimmingCharacters(in: .init(charactersIn: "\0"))
        
        if dataType == "flt " {
            let f = Float(rpm)
            let bits = f.bitPattern
            let bytes = [
                UInt8((bits >> 0) & 0xFF),
                UInt8((bits >> 8) & 0xFF),
                UInt8((bits >> 16) & 0xFF),
                UInt8((bits >> 24) & 0xFF)
            ]
            try writeKey(key, bytes: bytes, dataType: "flt ", dataSize: 4)
        } else {
            let bytes = doubleToSP78(rpm)
            try writeKey(key, bytes: bytes, dataType: dataType, dataSize: outputStruct.keyInfo.dataSize)
        }
    }

    private func readKey(_ key: String) throws -> SMCVal_t {
        var inputStruct  = SMCKeyData_t()
        var outputStruct = SMCKeyData_t()

        inputStruct.key = toFourCC(key)
        inputStruct.data8 = SMC_CMD_READ_KEYINFO

        try callSMC(&inputStruct, output: &outputStruct)
        
        if outputStruct.result == 0x84 {
            throw SMCError.keyNotFound(key)
        }

        var val = SMCVal_t()
        val.key = key
        val.dataSize = outputStruct.keyInfo.dataSize
        val.dataType = fromFourCC(outputStruct.keyInfo.dataType).trimmingCharacters(in: .init(charactersIn: "\0"))

        inputStruct.keyInfo = outputStruct.keyInfo
        inputStruct.keyInfo.dataSize = val.dataSize
        inputStruct.data8 = SMC_CMD_READ_BYTES

        try callSMC(&inputStruct, output: &outputStruct)

        val.bytes = withUnsafeBytes(of: outputStruct.bytes) { Array($0.prefix(Int(val.dataSize))) }
        return val
    }

    private func writeKey(_ key: String, bytes: [UInt8], dataType: String, dataSize: UInt32) throws {
        var inputStruct  = SMCKeyData_t()
        var outputStruct = SMCKeyData_t()

        inputStruct.key = toFourCC(key)
        inputStruct.data8 = SMC_CMD_READ_KEYINFO

        try callSMC(&inputStruct, output: &outputStruct)

        inputStruct.keyInfo = outputStruct.keyInfo
        inputStruct.data8 = SMC_CMD_WRITE_BYTES
        inputStruct.keyInfo.dataSize = dataSize

        withUnsafeMutableBytes(of: &inputStruct.bytes) { ptr in
            for (i, byte) in bytes.prefix(Int(dataSize)).enumerated() {
                ptr[i] = byte
            }
        }

        try callSMC(&inputStruct, output: &outputStruct)

        if outputStruct.result != 0 {
            throw SMCError.writeFailed("\(key) - HexCode: 0x\(String(format: "%X", outputStruct.result))")
        }
    }

    private func callSMC(_ input: inout SMCKeyData_t, output: inout SMCKeyData_t) throws {
        let inputSize  = MemoryLayout<SMCKeyData_t>.size
        var outputSize = MemoryLayout<SMCKeyData_t>.size

        let result = IOConnectCallStructMethod(
            connection,
            UInt32(KERNEL_INDEX_SMC),
            &input,  inputSize,
            &output, &outputSize
        )

        guard result == kIOReturnSuccess else {
            if result == kIOReturnNotPrivileged {
                throw SMCError.permissionDenied
            }
            throw SMCError.readFailed("IOConnectCallStructMethod failed: \(String(format: "0x%x", result))")
        }
    }
}
