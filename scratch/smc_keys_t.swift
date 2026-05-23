import Foundation
import IOKit

struct SMCKeyData_vers_t {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

struct SMCKeyData_pLimitData_t {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

struct SMCKeyData_keyInfo_t {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

struct SMCKeyData_t {
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

func toFourCC(_ string: String) -> UInt32 {
    var result: UInt32 = 0
    for char in string.utf8.prefix(4) {
        result = (result << 8) | UInt32(char)
    }
    return result
}

func fromFourCC(_ value: UInt32) -> String {
    var chars: [Character] = []
    for i in stride(from: 24, through: 0, by: -8) {
        let byte = UInt8((value >> i) & 0xFF)
        chars.append(Character(UnicodeScalar(byte)))
    }
    return String(chars)
}

let kIOACPIClassName = "AppleSMC"
var connection: io_connect_t = 0
let service: io_service_t = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOACPIClassName))
IOServiceOpen(service, mach_task_self_, 0, &connection)
IOObjectRelease(service)

func callSMC(input: inout SMCKeyData_t, output: inout SMCKeyData_t) -> Bool {
    let inputSize = MemoryLayout<SMCKeyData_t>.size
    var outputSize = MemoryLayout<SMCKeyData_t>.size
    let result = IOConnectCallStructMethod(connection, 2, &input, inputSize, &output, &outputSize)
    return result == kIOReturnSuccess && output.result == 0
}

func readKeyCount() -> Int {
    var input = SMCKeyData_t()
    var output = SMCKeyData_t()
    input.key = toFourCC("#KEY")
    input.data8 = 9 // READ_KEYINFO
    if callSMC(input: &input, output: &output) {
        input.keyInfo = output.keyInfo
        input.data8 = 5 // READ_BYTES
        if callSMC(input: &input, output: &output) {
            let count = (UInt32(output.bytes.0) << 24) | (UInt32(output.bytes.1) << 16) | (UInt32(output.bytes.2) << 8) | UInt32(output.bytes.3)
            return Int(count)
        }
    }
    return 0
}

func readKeyAtIndex(_ index: Int) -> String? {
    var input = SMCKeyData_t()
    var output = SMCKeyData_t()
    input.data8 = 8 // READ_INDEX
    input.data32 = UInt32(index)
    if callSMC(input: &input, output: &output) {
        return fromFourCC(output.key)
    }
    return nil
}

func readKeyInfo(_ key: String) -> SMCKeyData_keyInfo_t? {
    var input = SMCKeyData_t()
    var output = SMCKeyData_t()
    input.key = toFourCC(key)
    input.data8 = 9 // READ_KEYINFO
    if callSMC(input: &input, output: &output) {
        return output.keyInfo
    }
    return nil
}

let count = readKeyCount()
for i in 0..<count {
    if let key = readKeyAtIndex(i), key.hasPrefix("T") || key.hasPrefix("T") {
        if let info = readKeyInfo(key) {
            let type = fromFourCC(info.dataType).trimmingCharacters(in: .init(charactersIn: "\0"))
            print("Key: \(key) Type: \(type) Size: \(info.dataSize) Attr: \(info.dataAttributes)")
        } else {
            print("Key: \(key)")
        }
    }
}
