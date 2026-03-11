import Foundation
import IOKit.pwr_mgt
import os

let sleepLogger = Logger(subsystem: "com.chargecontrol.daemon", category: "SleepWake")

final class SleepWakeHandler {
    static let shared = SleepWakeHandler()
    
    // Core IOKit Message Macros ported to Swift
    private static let sys_iokit: UInt32 = (0x38 & 0x3f) << 26
    private static let sub_iokit_common: UInt32 = (0 & 0xfff) << 14
    
    private static func iokit_common_msg(_ message: UInt32) -> UInt32 {
        return sys_iokit | sub_iokit_common | message
    }
    
    private let kIOMessageCanSystemSleep = iokit_common_msg(0x270)
    private let kIOMessageSystemWillSleep = iokit_common_msg(0x280)
    private let kIOMessageSystemHasPoweredOn = iokit_common_msg(0x300)
    
    private var notifyPortRef: IONotificationPortRef?
    private var notifierObject: io_object_t = 0
    private(set) var rootPort: io_connect_t = 0

    private init() {}

    func start() {
        let callback: IOServiceInterestCallback = { refCon, service, messageType, messageArgument in
            let handler = SleepWakeHandler.shared
            if messageType == handler.kIOMessageCanSystemSleep || messageType == handler.kIOMessageSystemWillSleep {
                sleepLogger.debug("System will sleep")
                IOAllowPowerChange(handler.rootPort, Int(bitPattern: messageArgument))
            } else if messageType == handler.kIOMessageSystemHasPoweredOn {
                sleepLogger.debug("System powered on (woke up)")
                // Check battery state when system wakes up to re-apply any SMC limits
                PowerMonitor.shared.checkBatteryState()
            }
        }
        
        self.rootPort = IORegisterForSystemPower(
            nil,
            &self.notifyPortRef,
            callback,
            &self.notifierObject
        )
        
        if self.rootPort != 0, let notifyPortRef = self.notifyPortRef {
            IONotificationPortSetDispatchQueue(notifyPortRef, DispatchQueue.main)
            sleepLogger.info("Registered for system sleep/wake power events.")
        } else {
            sleepLogger.error("Failed to register for system power events.")
        }
    }
}
