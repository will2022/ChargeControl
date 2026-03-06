import Foundation
import os

let pmLogger = Logger(subsystem: "com.chargecontrol.daemon", category: "PowerManagement")

enum PowerManagement {
    static func setSleepDisabled(_ disabled: Bool) {
        pmLogger.info("Setting SleepDisabled to \(disabled)")
        let value: CFBoolean = disabled ? kCFBooleanTrue : kCFBooleanFalse
        let key = "SleepDisabled" as CFString
        let result = IOPMSetSystemPowerSetting(key, value)
        if result != 0 {
            pmLogger.error("Failed to set SleepDisabled to \(disabled): \(result)")
        }
    }
    
    static func restore() {
        // Ensure sleep is enabled on startup/shutdown unless we explicitly disable it later
        setSleepDisabled(false)
    }
}
