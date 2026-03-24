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
    var padding_vers: (UInt8, UInt8) = (0,0) // 2 bytes padding to align pLimitData to 4
    var pLimitData: SMCKeyData_pLimitData_t = SMCKeyData_pLimitData_t()
    var keyInfo: SMCKeyData_keyInfo_t = SMCKeyData_keyInfo_t()
    var padding_keyInfo: (UInt8, UInt8, UInt8) = (0,0,0) // 3 bytes padding
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var padding_data8: UInt8 = 0 // 1 byte padding to align data32 to 4
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
    guard bytes.count >= 2 else { return 0.0 }
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
            do {
                let celsius = try readTemperatureKey(entry.key)
                // 125+ usually indicates an unconnected/disabled Intel sensor (often 128 or 129)
                if celsius > 0 && celsius < 125.0 {
                    readings.append(SensorReading(
                        id: entry.key,
                        name: entry.name,
                        group: entry.group,
                        celsius: celsius
                    ))
                }
            } catch {
                // Ignore missing keys silently
            }
        }
        return readings
    }

    func fanCount() throws -> Int {
        let val = try readKey(kFanCountKey)
        guard val.bytes.count >= 1 else { return 0 }
        return Int(val.bytes[0])
    }

    func readFan(index: Int) throws -> FanStatus {
        let count = try fanCount()
        guard index < count else {
            throw SMCError.keyNotFound("Fan index \(index) out of range (count: \(count))")
        }

        let actualRPM  = Int(try readRPMKey(kFanActualRPM(index)))
        let minRPM     = Int(try readRPMKey(kFanMinRPM(index)))
        let maxRPM     = Int(try readRPMKey(kFanMaxRPM(index)))

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
        try setFanManualMode(index: index, manual: true)
        let key = kFanTargetRPM(index)
        let bytes = doubleToSP78(Double(rpm))
        try writeKey(key, bytes: bytes, dataType: "sp78", dataSize: 2)
    }

    func resetFan(index: Int) throws {
        try setFanManualMode(index: index, manual: false)
    }

    private func setFanManualMode(index: Int, manual: Bool) throws {
        // 'FS! ' is a ui16 bitmask where bit `index` controls manual override for Fan `index`
        // On modern Intel Macs, 'FS! ' is often missing or read-only, replaced by 'F0Md', 'F1Md', etc.
        let fsKey = "FS! "
        do {
            let val = try readKey(fsKey)
            var currentMask: UInt16 = 0
            if val.bytes.count >= 2 {
                currentMask = (UInt16(val.bytes[0]) << 8) | UInt16(val.bytes[1])
            }
            if manual {
                currentMask |= (1 << index)
            } else {
                currentMask &= ~(1 << index)
            }
            let bytes = [UInt8(currentMask >> 8), UInt8(currentMask & 0xFF)]
            try writeKey(fsKey, bytes: bytes, dataType: "ui16", dataSize: 2)
            return // Success with FS!
        } catch {
            // Ignore FS! error and attempt F{index}Md fallback
        }

        let fMdKey = "F\(index)Md"
        let bytes: [UInt8] = [manual ? 1 : 0]
        try writeKey(fMdKey, bytes: bytes, dataType: "ui8", dataSize: 1)
    }

    // MARK: - Private IOKit Helpers

    private func readRPMKey(_ key: String) throws -> Double {
        let val = try readKey(key)
        if val.dataType == "flt " && val.dataSize == 4 && val.bytes.count >= 4 {
            let num = val.bytes.withUnsafeBytes { $0.load(as: UInt32.self) }
            
            // Try natively (usually little-endian on Intel)
            let dNative = Double(Float(bitPattern: num))
            if !dNative.isNaN && !dNative.isInfinite && dNative >= 0 && dNative <= 20000 {
                return min(max(dNative, 0.0), 20000.0)
            }
            
            // Fallback to swapped (Big-Endian)
            let dSwapped = Double(Float(bitPattern: num.byteSwapped))
            return dSwapped.isNaN || dSwapped.isInfinite ? 0.0 : min(max(dSwapped, 0.0), 20000.0)
        }
        let d = sp78ToDouble(val.bytes)
        return d.isNaN || d.isInfinite ? 0.0 : min(max(d, 0.0), 20000.0)
    }

    private func readTemperatureKey(_ key: String) throws -> Double {
        let val = try readKey(key)
        // Temperature keys use "sp78" (same as fans) or "flt " type
        if val.dataType == "sp78" {
            guard val.bytes.count >= 2 else { return 0.0 }
            // sp78: low byte is fractional, value / 256
            let raw = (Int(val.bytes[0]) << 8) | Int(val.bytes[1])
            return Double(raw) / 256.0
        } else if val.dataType == "flt " && val.bytes.count >= 4 {
            // IEEE 754 float
            let num = val.bytes.withUnsafeBytes { $0.load(as: UInt32.self) }
            
            // Try natively (usually little-endian on Intel)
            let dNative = Double(Float(bitPattern: num))
            if !dNative.isNaN && !dNative.isInfinite && dNative >= -100 && dNative <= 300 {
                return min(max(dNative, -100.0), 300.0)
            }
            
            // Fallback to swapped (Big-Endian)
            let dSwapped = Double(Float(bitPattern: num.byteSwapped))
            return dSwapped.isNaN || dSwapped.isInfinite ? 0.0 : min(max(dSwapped, -100.0), 300.0)
        }
        
        guard val.bytes.count >= 1 else { return 0.0 }
        let d = Double(val.bytes[0])
        return d.isNaN || d.isInfinite ? 0.0 : min(max(d, -100.0), 300.0)
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
