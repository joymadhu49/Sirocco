// Chip temperature, power source and user idle time.
import Foundation
import IOKit
import IOKit.ps

// IOHIDEventSystemClient is private API, but it is the only place Apple Silicon publishes the
// per-die temperatures (the "PMU tdie" sensors). These are the symbols every temperature tool
// on Apple Silicon links against.
@_silgen_name("IOHIDEventSystemClientCreate")
private func IOHIDEventSystemClientCreate(_ allocator: CFAllocator?) -> Unmanaged<AnyObject>
@_silgen_name("IOHIDEventSystemClientSetMatching")
private func IOHIDEventSystemClientSetMatching(_ client: AnyObject, _ matching: CFDictionary) -> Int32
@_silgen_name("IOHIDEventSystemClientCopyServices")
private func IOHIDEventSystemClientCopyServices(_ client: AnyObject) -> Unmanaged<CFArray>?
@_silgen_name("IOHIDServiceClientCopyProperty")
private func IOHIDServiceClientCopyProperty(_ service: AnyObject, _ key: CFString) -> Unmanaged<AnyObject>?
@_silgen_name("IOHIDServiceClientCopyEvent")
private func IOHIDServiceClientCopyEvent(_ service: AnyObject, _ type: Int64, _ options: Int32, _ timestamp: Int64) -> Unmanaged<AnyObject>?
@_silgen_name("IOHIDEventGetFloatValue")
private func IOHIDEventGetFloatValue(_ event: AnyObject, _ field: Int32) -> Double

enum Sensors {
    private static let temperatureEvent: Int64 = 15
    private static let client: AnyObject = {
        let client = IOHIDEventSystemClientCreate(kCFAllocatorDefault).takeRetainedValue()
        // Usage page 0xff00, usage 5: Apple vendor temperature sensors.
        _ = IOHIDEventSystemClientSetMatching(client, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
        return client
    }()

    /// Hottest CPU/GPU die, in °C. Nil when no die sensor answers.
    static func chipTemperature() -> Double? {
        guard let services = IOHIDEventSystemClientCopyServices(client)?.takeRetainedValue() as? [AnyObject] else {
            return nil
        }
        var hottest: Double?
        for service in services {
            guard let name = IOHIDServiceClientCopyProperty(service, "Product" as CFString)?.takeRetainedValue() as? String,
                  name.hasPrefix("PMU tdie"),
                  let event = IOHIDServiceClientCopyEvent(service, temperatureEvent, 0, 0)?.takeRetainedValue()
            else { continue }
            let value = IOHIDEventGetFloatValue(event, Int32(temperatureEvent << 16))
            if value > 0, value < 130 { hottest = max(hottest ?? value, value) }
        }
        return hottest
    }

    static func onACPower() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() as String?
        else { return false }
        return type == kIOPMACPowerKey
    }

    /// Battery percentage and whether it is charging, for display.
    static func battery() -> (percent: Int, charging: Bool)? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for source in list {
            guard let info = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                  let percent = info[kIOPSCurrentCapacityKey] as? Int
            else { continue }
            return (percent, info[kIOPSIsChargingKey] as? Bool ?? false)
        }
        return nil
    }

    /// Seconds since the last keyboard, mouse or trackpad input, for any user session.
    static func idleSeconds() -> Double {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        guard service != 0 else { return 0 }
        defer { IOObjectRelease(service) }
        guard let value = IORegistryEntryCreateCFProperty(service, "HIDIdleTime" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
        else { return 0 }
        if let number = value as? NSNumber { return number.doubleValue / 1_000_000_000 }
        if let data = value as? Data, data.count >= 8 {
            return Double(data.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }) / 1_000_000_000
        }
        return 0
    }
}
