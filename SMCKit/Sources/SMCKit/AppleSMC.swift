// AppleSMC.swift
// Intel Mac SMC backend using IOKit.
// Accesses the SMC via IOServiceGetMatchingService / IOConnectCallStructMethod.

import Foundation
import IOKit

// MARK: - IOKit Helpers

private let kIOACPIClassName = "AppleSMC"

private struct SMCKeyData_t {
    var key: UInt32 = 0
    var vers: SMCKeyData_vers_t = SMCKeyData_vers_t()
    var pLimitData: SMCKeyData_pLimitData_t = SMCKeyData_pLimitData_t()
    var keyInfo: SMCKeyData_keyInfo_t = SMCKeyData_keyInfo_t()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (
        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    )
}

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

private struct SMCVal_t {
    var key: String = ""
    var dataSize: UInt32 = 0
    var dataType: String = ""
    var bytes: [UInt8] = Array(repeating: 0, count: 32)
}

private let KERNEL_INDEX_SMC = 2
private let SMC_CMD_READ_BYTES: UInt8 = 5
private let SMC_CMD_WRITE_BYTES: UInt8 = 6
private let SMC_CMD_READ_INDEX: UInt8 = 8
private let SMC_CMD_READ_KEYINFO: UInt8 = 9

// MARK: - FourCC helpers

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

// MARK: - Known SMC Keys

/// Temperature keys for Intel Macs.
/// Keys sourced from open SMC documentation (e.g., OSXIdonotknow, smckit).
private let kTemperatureKeys: [(key: String, name: String, group: SensorGroup)] = [
    ("TC0C", "CPU Core 0",  .cpuCore),
    ("TC1C", "CPU Core 1",  .cpuCore),
    ("TC2C", "CPU Core 2",  .cpuCore),
    ("TC3C", "CPU Core 3",  .cpuCore),
    ("TC4C", "CPU Core 4",  .cpuCore),
    ("TC5C", "CPU Core 5",  .cpuCore),
    ("TC6C", "CPU Core 6",  .cpuCore),
    ("TC7C", "CPU Core 7",  .cpuCore),
    ("TCAD", "CPU Package", .cpuCore),
    ("TGDD", "GPU Die",     .gpu),
    ("TG0D", "GPU 0 Die",   .gpu),
    ("TG1D", "GPU 1 Die",   .gpu),
    ("TNSL", "NAND Flash",  .nand),
    ("TN0C", "NAND 0",      .nand),
]

/// Fan SMC key patterns.
/// Fan N actual RPM:   F{N}Ac  (sp78 type)
/// Fan N minimum RPM:  F{N}Mn  (sp78 type)
/// Fan N maximum RPM:  F{N}Mx  (sp78 type)
/// Fan N target RPM:   F{N}Tg  (sp78 type)  ← we write this for control
/// Fan count:          FNum    (uint8 type)
private let kFanCountKey = "FNum"
private func kFanActualRPM(_ index: Int) -> String { "F\(index)Ac" }
private func kFanMinRPM(_ index: Int) -> String     { "F\(index)Mn" }
private func kFanMaxRPM(_ index: Int) -> String     { "F\(index)Mx" }
private func kFanTargetRPM(_ index: Int) -> String  { "F\(index)Tg" }

// MARK: - sp78 Encoding

/// sp78 is a fixed-point format used by SMC for fan speeds.
/// Value = bytes[0] << 6 | bytes[1] >> 2
private func sp78ToDouble(_ bytes: [UInt8]) -> Double {
    let raw = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
    return Double(raw) / 4.0
}

private func doubleToSP78(_ value: Double) -> [UInt8] {
    let raw = UInt16(value * 4.0)
    return [UInt8(raw >> 8), UInt8(raw & 0xFF)]
}

// MARK: - AppleSMC

/// Intel Mac SMC backend using raw IOKit calls.
final class AppleSMC: SMCProvider {

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

    // MARK: SMCProvider

    func readTemperatures() throws -> [SensorReading] {
        var readings: [SensorReading] = []
        for entry in kTemperatureKeys {
            if let celsius = try? readTemperatureKey(entry.key), celsius > 0 {
                readings.append(SensorReading(
                    id: entry.key,
                    name: entry.name,
                    group: entry.group,
                    celsius: celsius
                ))
            }
        }
        return readings
    }

    func fanCount() throws -> Int {
        let val = try readKey(kFanCountKey)
        return Int(val.bytes[0])
    }

    func readFan(index: Int) throws -> FanStatus {
        let count = try fanCount()
        guard index < count else {
            throw SMCError.keyNotFound("Fan index \(index) out of range (count: \(count))")
        }

        let actualRPM  = Int(sp78ToDouble(try readKey(kFanActualRPM(index)).bytes))
        let minRPM     = Int(sp78ToDouble(try readKey(kFanMinRPM(index)).bytes))
        let maxRPM     = Int(sp78ToDouble(try readKey(kFanMaxRPM(index)).bytes))

        // Distinguish left/right fans on MacBook Pros
        let name: String
        if count == 2 {
            name = index == 0 ? "Left Fan" : "Right Fan"
        } else {
            name = "Fan \(index)"
        }

        return FanStatus(
            id: index,
            name: name,
            currentRPM: actualRPM,
            minRPM: minRPM,
            maxRPM: maxRPM,
            isManaged: false  // Updated by daemon based on active profile
        )
    }

    func setFanMinRPM(index: Int, rpm: Int) throws {
        let key = kFanTargetRPM(index)
        let bytes = doubleToSP78(Double(rpm))
        try writeKey(key, bytes: bytes, dataType: "sp78", dataSize: 2)
    }

    func resetFan(index: Int) throws {
        // Restore Apple's automatic fan control by writing 0 to target RPM.
        // On most Intel Macs, writing 0 or min to F{N}Tg hands back control.
        try writeKey(kFanTargetRPM(index), bytes: [0, 0], dataType: "sp78", dataSize: 2)
    }

    // MARK: - Private IOKit Helpers

    private func readTemperatureKey(_ key: String) throws -> Double {
        let val = try readKey(key)
        // Temperature keys use "sp78" (same as fans) or "flt " type
        if val.dataType == "sp78" {
            // sp78: low byte is fractional, value / 256
            let raw = (Int(val.bytes[0]) << 8) | Int(val.bytes[1])
            return Double(raw) / 256.0
        } else if val.dataType == "flt " {
            // IEEE 754 float
            var floatVal: Float = 0
            withUnsafeMutableBytes(of: &floatVal) { ptr in
                for i in 0..<4 {
                    ptr[i] = val.bytes[3 - i] // big-endian
                }
            }
            return Double(floatVal)
        }
        return Double(val.bytes[0])
    }

    private func readKey(_ key: String) throws -> SMCVal_t {
        var inputStruct  = SMCKeyData_t()
        var outputStruct = SMCKeyData_t()

        inputStruct.key = toFourCC(key)
        inputStruct.data8 = SMC_CMD_READ_KEYINFO

        try callSMC(&inputStruct, output: &outputStruct)

        var val = SMCVal_t()
        val.key = key
        val.dataSize = outputStruct.keyInfo.dataSize
        val.dataType = fromFourCC(outputStruct.keyInfo.dataType).trimmingCharacters(in: .init(charactersIn: "\0"))

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

        inputStruct.data8 = SMC_CMD_WRITE_BYTES
        inputStruct.keyInfo.dataSize = dataSize

        withUnsafeMutableBytes(of: &inputStruct.bytes) { ptr in
            for (i, byte) in bytes.prefix(Int(dataSize)).enumerated() {
                ptr[i] = byte
            }
        }

        try callSMC(&inputStruct, output: &outputStruct)

        if outputStruct.result != 0 {
            throw SMCError.writeFailed(key)
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
