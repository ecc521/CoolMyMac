import Foundation
import IOKit

let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)
typealias IOHIDEventSystemClientCreateType = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
typealias IOHIDEventSystemClientCopyServicesType = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
typealias IOHIDServiceClientCopyPropertyType = @convention(c) (AnyObject, CFString) -> Unmanaged<AnyObject>?
typealias IOHIDServiceClientCopyEventType = @convention(c) (AnyObject, Int32, Int32, Int32) -> Unmanaged<AnyObject>?
typealias IOHIDEventGetFloatValueType = @convention(c) (AnyObject, Int32) -> Double

let IOHIDEventSystemClientCreate = unsafeBitCast(dlsym(handle, "IOHIDEventSystemClientCreate")!, to: IOHIDEventSystemClientCreateType.self)
let IOHIDEventSystemClientCopyServices = unsafeBitCast(dlsym(handle, "IOHIDEventSystemClientCopyServices")!, to: IOHIDEventSystemClientCopyServicesType.self)
let IOHIDServiceClientCopyProperty = unsafeBitCast(dlsym(handle, "IOHIDServiceClientCopyProperty")!, to: IOHIDServiceClientCopyPropertyType.self)
let IOHIDServiceClientCopyEvent = unsafeBitCast(dlsym(handle, "IOHIDServiceClientCopyEvent")!, to: IOHIDServiceClientCopyEventType.self)
let IOHIDEventGetFloatValue = unsafeBitCast(dlsym(handle, "IOHIDEventGetFloatValue")!, to: IOHIDEventGetFloatValueType.self)

guard let client = IOHIDEventSystemClientCreate(kCFAllocatorDefault)?.takeRetainedValue() else { exit(1) }
guard let services = IOHIDEventSystemClientCopyServices(client)?.takeRetainedValue() as? [AnyObject] else { exit(1) }

print("Found \(services.count) services")
var thermalCount = 0
for service in services {
    let name = (IOHIDServiceClientCopyProperty(service, "Product" as CFString)?.takeRetainedValue() as? String) ?? "Unknown"
    
    // Check if it's a thermal sensor
    if let event = IOHIDServiceClientCopyEvent(service, 15, 0, 0)?.takeRetainedValue() {
        let temp = IOHIDEventGetFloatValue(event, (15 << 16) | 1)
        print("Thermal Sensor: \(name) = \(temp) C")
        thermalCount += 1
    }
}
print("Total Thermal Sensors: \(thermalCount)")
