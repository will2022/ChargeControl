import Foundation
import os
import IOKit

let daemonLogger = Logger(subsystem: "com.chargecontrol.daemon", category: "Daemon")

public class ChargeControlDaemon: NSObject, ChargeControlDaemonProtocol {
    public static let shared = ChargeControlDaemon()
    
    // Caching for energy optimization
    private var lastThermalRead: Date = .distantPast
    private var cachedTemps: [String: Double] = [:]
    
    private override init() {
        super.init()
    }
    
    public func getUniqueId(reply: @escaping (String?) -> Void) {
        reply(Bundle.main.bundleIdentifier)
    }
    
    public func getState(reply: @escaping ([String: Any]?) -> Void) {
        let pm = PowerMonitor.shared
        var state: [String: Any] = [:]
        
        // 1. Logic State
        state["isChargingEnabled"] = pm.isChargingEnabledState
        state["adapterDisabledManual"] = pm.adapterDisabledManual
        state["chargingDisabledManual"] = pm.chargingDisabledManual
        state["chargingToFull"] = pm.chargingToFull
        state["floatingModeEnabled"] = pm.floatingModeEnabled
        state["powerUserMode"] = pm.powerUserModeEnabled
        
        // Legacy keys for UI compatibility
        state["chargingDisabled"] = pm.chargingDisabledManual
        state["adapterDisabled"] = pm.adapterDisabledManual
        state["maxLimit"] = pm.getMaxLimit()
        state["startLimit"] = pm.getStartLimit()
        state["floatingMode"] = pm.floatingModeEnabled
        state["audioWarningEnabled"] = pm.isAudioWarningEnabled()
        state["audioSoundName"] = pm.audioSoundName
        state["autoDischarge"] = pm.autoDischargeEnabled
        state["heatProtection"] = pm.heatProtectionEnabled
        state["heatThreshold"] = pm.heatThreshold
        state["magSafeSync"] = pm.magSafeSyncEnabled
        state["sleepDuringCharge"] = pm.disableSleepDuringCharge
        state["sleepDuringDischarge"] = pm.disableSleepDuringDischarge
        state["sleepAggressive"] = pm.disableSleepAggressive
        state["heatProtectionTriggered"] = pm.isHeatProtectionTriggered
        
        // 2. Thermal Telemetry (Rate-limited to 15s)
        let now = Date()
        if now.timeIntervalSince(lastThermalRead) > 15 {
            var temps: [String: Double] = [:]
            if let batt = SMCComm.readFloat("TB0T") {
                temps["Battery"] = Double(batt)
            }
            if let cpu = SMCComm.readFloat("TC0P") {
                temps["CPU"] = Double(cpu)
            }
            if let gpu = SMCComm.readFloat("TG0P") {
                temps["GPU"] = Double(gpu)
            }
            if let palm = SMCComm.readFloat("Ts0P") {
                temps["Palm Rest"] = Double(palm)
            }
            self.cachedTemps = temps
            self.lastThermalRead = now
        }
        state["temperatures"] = cachedTemps
        if let primary = cachedTemps["Battery"] ?? cachedTemps["CPU"] {
            state["batteryTemp"] = primary
        }
        
        // 3. Consolidated Battery Telemetry (from IOKit cached where possible)
        let bt = BatteryTelemetry.shared.getTelemetry()
        state["batterySerial"] = bt.serial
        state["batteryModel"] = bt.model
        state["nominalCapacity"] = bt.nominalChargeCapacity
        state["designCapacity"] = bt.designCapacity
        state["rawMaxCapacity"] = bt.appleRawMaxCapacity
        state["rawCurrentCapacity"] = bt.appleRawCurrentCapacity
        state["voltage"] = bt.voltage != nil ? Double(bt.voltage!) / 1000.0 : nil
        state["amperage"] = bt.amperage
        state["cycleCount"] = bt.cycleCount
        state["adapterWatts"] = bt.adapterWatts
        state["adapterDescription"] = bt.adapterDescription
        
        // Calculated/Legacy mappings
        if let amp = bt.amperage, let volt = state["voltage"] as? Double {
             state["batteryPowerWatts"] = (Double(amp) * volt) / 1000.0
        }
        
        reply(state)
    }
    
    public func getHistory(reply: @escaping ([[String : Any]]?) -> Void) {
        reply(Database.shared.getHistory())
    }
    
    public func getSettings(reply: @escaping ([String: Any]?) -> Void) {
        let pm = PowerMonitor.shared
        reply([
            "maxLimit": pm.getMaxLimit(),
            "startLimit": pm.getStartLimit(),
            "audioSoundName": pm.audioSoundName,
            "powerUserMode": pm.powerUserModeEnabled,
            "floatingMode": pm.floatingModeEnabled
        ])
    }
    
    public func setSettings(settings: [String: Any], reply: @escaping (Int32) -> Void) {
        let pm = PowerMonitor.shared
        
        if let limit = settings["maxLimit"] as? Int { pm.setMaxLimit(limit) }
        if let startLimit = settings["startLimit"] as? Int { pm.setStartLimit(startLimit) }
        if let floatingMode = settings["floatingMode"] as? Bool { pm.setFloatingMode(floatingMode) }
        if let powerUser = settings["powerUserMode"] as? Bool { pm.setPowerUserMode(powerUser) }
        
        reply(0)
    }
    
    public func execute(command: Int32, reply: @escaping (Int32) -> Void) {
        guard let cmd = ChargeControlCommand(rawValue: command) else {
            reply(-1)
            return
        }
        
        let pm = PowerMonitor.shared
        switch cmd {
        case .disablePowerAdapter: pm.disablePowerAdapter()
        case .enablePowerAdapter: pm.enablePowerAdapter()
        case .chargeToFull: pm.chargeToFullAction()
        case .chargeToLimit: pm.chargeToLimitAction()
        case .disableCharging: pm.disableChargingOnly()
        case .isSupported: break
        case .testMagSafe:
            _ = SMCComm.setMagSafeColor(.orange)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                _ = SMCComm.setMagSafeColor(.green)
            }
        @unknown default:
            break
        }
        reply(0)
    }
    
    public func getEnergyImpact(reply: @escaping ([String : Any]?) -> Void) {
        reply(EnergyMonitor.shared.getDiagnosticState())
    }
    
    public func getHistoricalEnergyImpact(reply: @escaping ([String : Any]?) -> Void) {
        let data = Database.shared.getHistoricalEnergyImpact()
        reply(["consumers": data])
    }
}
