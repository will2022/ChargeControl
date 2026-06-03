import Foundation
import IOKit
import os

let telemetryLogger = Logger(subsystem: "com.chargecontrol.daemon", category: "BatteryTelemetry")

class BatteryTelemetry {
    static let shared = BatteryTelemetry()
    
    struct BatteryData {
        var serial: String?
        var model: String?
        var nominalChargeCapacity: Int?
        var designCapacity: Int?
        var appleRawMaxCapacity: Int?
        var appleRawCurrentCapacity: Int?
        var voltage: Int?
        var amperage: Int?
        var cycleCount: Int?
        var temp: Int?
        var adapterWatts: Int?
        var adapterDescription: String?
    }
    
    private init() {}
    
    // Cache for static data
    private var cachedSerial: String?
    private var cachedModel: String?
    private var cachedDesignCapacity: Int?
    private var cachedNominalCapacity: Int?
    
    func getTelemetry() -> BatteryData {
        var data = BatteryData()
        
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else {
            telemetryLogger.error("Failed to find AppleSmartBattery service")
            return data
        }
        defer { IOObjectRelease(service) }
        
        // Helper to read properties
        func readInt(_ key: String) -> Int? {
            guard let prop = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0) else { return nil }
            let val = prop.takeRetainedValue()
            if let num = val as? NSNumber { return num.intValue }
            if let num = val as? Int { return num }
            return nil
        }
        
        func readString(_ key: String) -> String? {
            guard let prop = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0) else { return nil }
            return prop.takeRetainedValue() as? String
        }
        
        // 1. Static Metadata (Cached)
        if cachedSerial == nil { cachedSerial = readString("Serial") }
        if cachedModel == nil { cachedModel = readString("DeviceName") }
        if cachedDesignCapacity == nil { cachedDesignCapacity = readInt("DesignCapacity") }
        if cachedNominalCapacity == nil { cachedNominalCapacity = readInt("NominalChargeCapacity") }
        
        data.serial = cachedSerial
        data.model = cachedModel
        data.designCapacity = cachedDesignCapacity
        data.nominalChargeCapacity = cachedNominalCapacity
        
        // 2. Core Energy Stats (Live)
        data.appleRawMaxCapacity = readInt("AppleRawMaxCapacity")
        data.appleRawCurrentCapacity = readInt("AppleRawCurrentCapacity")
        data.voltage = readInt("Voltage")
        data.cycleCount = readInt("CycleCount")
        data.temp = readInt("Temperature")
        
        // Amperage can be signed/unsigned depending on IOKit entry
        if let prop = IORegistryEntryCreateCFProperty(service, "InstantAmperage" as CFString, kCFAllocatorDefault, 0) {
            let val = prop.takeRetainedValue()
            if let num = val as? NSNumber {
                data.amperage = num.intValue
            }
        } else if let prop = IORegistryEntryCreateCFProperty(service, "Amperage" as CFString, kCFAllocatorDefault, 0) {
              let val = prop.takeRetainedValue()
              if let num = val as? NSNumber {
                  // Handle potential UInt wrap-around for negative amperage
                  let raw = num.uint64Value
                  if raw > 0x7FFFFFFFFFFFFFFF {
                      data.amperage = Int(Int64(bitPattern: raw))
                  } else {
                      data.amperage = Int(raw)
                  }
              }
        }
        
        // 3. Adapter Details
        if let prop = IORegistryEntryCreateCFProperty(service, "AdapterDetails" as CFString, kCFAllocatorDefault, 0) {
            let dict = prop.takeRetainedValue() as? [String: Any]
            data.adapterWatts = dict?["Watts"] as? Int
            data.adapterDescription = dict?["Description"] as? String
        }
        
        return data
    }
}
