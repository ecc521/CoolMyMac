import Foundation
import IOKit

let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)
typealias IOHIDEventSystemClientCreateType = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
typealias IOHIDEventSystemClientCopyServicesType = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
typealias IOHIDServiceClientCopyPropertyType = @convention(c) (AnyObject, CFString) -> Unmanaged<AnyObject>?

let IOHIDEventSystemClientCreate = unsafeBitCast(dlsym(handle, "IOHIDEventSystemClientCreate")!, to: IOHIDEventSystemClientCreateType.self)
let IOHIDEventSystemClientCopyServices = unsafeBitCast(dlsym(handle, "IOHIDEventSystemClientCopyServices")!, to: IOHIDEventSystemClientCopyServicesType.self)
let IOHIDServiceClientCopyProperty = unsafeBitCast(dlsym(handle, "IOHIDServiceClientCopyProperty")!, to: IOHIDServiceClientCopyPropertyType.self)

guard let client = IOHIDEventSystemClientCreate(kCFAllocatorDefault)?.takeRetainedValue() else { exit(1) }
guard let services = IOHIDEventSystemClientCopyServices(client)?.takeRetainedValue() as? [AnyObject] else { exit(1) }

for service in services {
    let name = (IOHIDServiceClientCopyProperty(service, "Product" as CFString)?.takeRetainedValue() as? String) ?? "Unknown"
    
    // Check property
    if let tempNum = IOHIDServiceClientCopyProperty(service, "CurrentTemperature" as CFString)?.takeRetainedValue() as? NSNumber {
        print("Prop Thermal: \(name) = \(tempNum.doubleValue) C")
    }
}
