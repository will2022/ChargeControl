import Foundation
import os
import IOKit.pwr_mgt

let pmLogger = Logger(subsystem: "com.chargecontrol.daemon", category: "PowerManagement")

enum PowerManagement {
    private static var assertionID: IOPMAssertionID = 0
    
    static func setSleepDisabled(_ disabled: Bool, aggressive: Bool = false) {
        pmLogger.info("Setting SleepDisabled to \(disabled) (aggressive: \(aggressive))")
        
        // 1. Handle Aggressive Mode (Global System Setting)
        let value: CFBoolean = (disabled && aggressive) ? kCFBooleanTrue : kCFBooleanFalse
        let key = "SleepDisabled" as CFString
        let result = IOPMSetSystemPowerSetting(key, value)
        if result != 0 {
            pmLogger.error("Failed to set SleepDisabled to \(disabled): \(result)")
        }
        
        // 2. Handle Standard Mode (Power Assertion)
        if disabled && !aggressive {
            if assertionID == 0 {
                let reasonForActivity = "ChargeControl enforcing battery limits" as CFString
                let success = IOPMAssertionCreateWithName(
                    kIOPMAssertionTypePreventSystemSleep as CFString,
                    IOPMAssertionLevel(kIOPMAssertionLevelOn),
                    reasonForActivity,
                    &assertionID
                )
                if success == kIOReturnSuccess {
                    pmLogger.info("Successfully created PreventSystemSleep assertion: \(assertionID)")
                } else {
                    pmLogger.error("Failed to create PreventSystemSleep assertion: \(success)")
                    assertionID = 0
                }
            }
        } else {
            if assertionID != 0 {
                let result = IOPMAssertionRelease(assertionID)
                if result == kIOReturnSuccess {
                    pmLogger.info("Successfully released PreventSystemSleep assertion: \(assertionID)")
                } else {
                    pmLogger.error("Failed to release PreventSystemSleep assertion: \(result)")
                }
                assertionID = 0
            }
        }
    }
    
    static func restore() {
        // Ensure sleep is enabled on startup/shutdown unless we explicitly disable it later
        setSleepDisabled(false, aggressive: false)
        setSleepDisabled(false, aggressive: true)
    }
}
