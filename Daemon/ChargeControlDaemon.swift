import Foundation
import os

let daemonLogger = Logger(subsystem: "com.chargecontrol.daemon", category: "Daemon")

public class ChargeControlDaemon: NSObject, ChargeControlDaemonProtocol {
    public static let shared = ChargeControlDaemon()
    
    private override init() {
        super.init()
    }
    
    public func getUniqueId(reply: @escaping (String?) -> Void) {
        reply(Bundle.main.bundleIdentifier)
    }
    public func getState(reply: @escaping ([String: Any]?) -> Void) {
        var state: [String: Any] = [:]

        let pm = PowerMonitor.shared
        state["chargingDisabled"] = pm.chargingDisabledManual
        state["adapterDisabled"] = pm.adapterDisabledManual

        state["maxLimit"] = pm.getMaxLimit()
        state["startLimit"] = pm.getStartLimit()
        state["floatingMode"] = pm.floatingModeEnabled
        state["audioWarningEnabled"] = pm.isAudioWarningEnabled()
        state["audioSoundName"] = pm.audioSoundName
        state["chargingToFull"] = pm.chargingToFull

        state["autoDischarge"] = pm.autoDischargeEnabled
        state["heatProtection"] = pm.heatProtectionEnabled
        state["heatThreshold"] = pm.heatThreshold
        state["magSafeSync"] = pm.magSafeSyncEnabled
        state["sleepDuringCharge"] = pm.disableSleepDuringCharge
        state["sleepDuringDischarge"] = pm.disableSleepDuringDischarge
        state["heatProtectionTriggered"] = pm.isHeatProtectionTriggered
        state["powerUserMode"] = pm.powerUserModeEnabled
        
        // --- Expanded SMC Analytics ---
        // 1. Thermal Sensors
        var temps: [String: Double] = [:]
        let tempKeys = [
            "CPU": "TC0P", "GPU": "TG0P", "Battery": "B0Te",
            "Logic Board": "TL0P", "Heat Pipe": "Th0H"
        ]
        for (name, key) in tempKeys {
            if let t = SMCComm.readTemperature(key) {
                temps[name] = t
            }
        }
        if let palm = SMCComm.readFloat("Ts0P") {
            temps["Palm Rest"] = Double(palm)
        }
        state["temperatures"] = temps
        if let primary = temps["Battery"] ?? temps["CPU"] {
            state["batteryTemp"] = primary
        }
        
        // 2. Power Telemetry (Validated Decodings)
        var ampValue: Int?
        if let amp = SMCComm.readInt16BE("B0AC") {
            ampValue = Int(amp)
            state["amperage"] = ampValue
        }
        
        if let volt = SMCComm.readUInt16LE("B0AV") {
            state["voltage"] = Double(volt) / 1000.0
        }

        var adapterWatts: Double?
        if let aw = SMCComm.readFloat("PDTR") {
            adapterWatts = Double(aw)
            state["adapterWatts"] = Int(aw)
        }

        if let systemWatts = SMCComm.readFloat("PSTR") {
            state["systemPowerWatts"] = Double(systemWatts)
            
            // Calculate Battery Flow
            if let adapter = adapterWatts {
                state["batteryPowerWatts"] = adapter - Double(systemWatts)
            } else if pm.adapterDisabledManual || (pm.floatingModeEnabled && !pm.isChargingEnabledState) {
                // Adapter is isolated, we know flow is exactly -system load
                state["batteryPowerWatts"] = -Double(systemWatts)
            } else if let amp = ampValue, let volt = state["voltage"] as? Double {
                // Fallback to amperage * voltage (with sanity check)
                let calculated = (Double(amp) * volt) / 1000.0
                if calculated < 150.0 && calculated > -150.0 {
                    state["batteryPowerWatts"] = calculated
                }
            }
        }
        
        // 3. Health & Capacity
        if let cycles = SMCComm.readUInt16LE("B0CT") {
            state["cycleCount"] = Int(cycles)
        }
        
        if let maxCap = SMCComm.readUInt16LE("B0FC") {
            state["maxCapacity"] = Int(maxCap)
        }
        
        if let designCap = SMCComm.readUInt16LE("B0DC") {
            state["designCapacity"] = Int(designCap)
        }
        
        if let currentCap = SMCComm.readUInt16BE("B0RM") {
            state["currentCapacity"] = Int(currentCap)
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
            "audioSoundName": pm.audioSoundName
        ])
    }
    
    public func setSettings(settings: [String: Any], reply: @escaping (Int32) -> Void) {
        let pm = PowerMonitor.shared
        
        if let limit = settings["maxLimit"] as? Int {
            pm.setMaxLimit(limit)
        }
        
        if let startLimit = settings["startLimit"] as? Int {
            pm.setStartLimit(startLimit)
        }

        if let floatingMode = settings["floatingMode"] as? Bool {
            pm.setFloatingMode(floatingMode)
        }
        
        if let audioEnabled = settings["audioWarningEnabled"] as? Bool {
            pm.setAudioWarningEnabled(audioEnabled)
        }
        
        if let audioSoundName = settings["audioSoundName"] as? String {
            pm.setAudioSoundName(audioSoundName)
        }

        if let autoDischarge = settings["autoDischarge"] as? Bool {
            pm.setAutoDischarge(autoDischarge)
        }

        if let heatEnabled = settings["heatProtection"] as? Bool,
           let heatThreshold = settings["heatThreshold"] as? Double {
            pm.setHeatProtection(heatEnabled, threshold: heatThreshold)
        }

        if let magSafeSync = settings["magSafeSync"] as? Bool {
            pm.setMagSafeSync(magSafeSync)
        }

        if let sleepCharge = settings["sleepDuringCharge"] as? Bool,
           let sleepDischarge = settings["sleepDuringDischarge"] as? Bool {
            pm.setSleepSettings(disableDuringCharge: sleepCharge, disableDuringDischarge: sleepDischarge)
        }

        if let powerUser = settings["powerUserMode"] as? Bool {
            pm.setPowerUserMode(powerUser)
        }
        
        reply(0)
    }
    
    public func execute(command: Int32, reply: @escaping (Int32) -> Void) {
        guard let cmd = ChargeControlCommand(rawValue: command) else {
            daemonLogger.error("Received unknown command: \(command)")
            reply(-1)
            return
        }
        
        daemonLogger.info("Executing command: \(String(describing: cmd))")
        var success = false
        let pm = PowerMonitor.shared
        
        switch cmd {
        case .disablePowerAdapter:
            pm.setAdapterDisabledManual(true)
            success = true
        case .enablePowerAdapter:
            pm.setAdapterDisabledManual(false)
            success = true
        case .chargeToFull:
            pm.chargingDisabledManual = false
            pm.chargingToFull = true
            pm.checkBatteryState()
            success = true
        case .chargeToLimit:
            pm.chargingDisabledManual = false
            pm.chargingToFull = false
            pm.checkBatteryState()
            success = true
        case .disableCharging:
            pm.chargingToFull = false
            pm.setChargingDisabledManual(true)
            success = true
        case .testMagSafe:
            _ = SMCComm.setMagSafeColor(.orangeSlowBlink)
            // Revert after 5 seconds by triggering a full state check
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                pm.checkBatteryState()
            }
            success = true
        case .isSupported:
            success = SMCComm.open()
        }
        
        daemonLogger.info("Command \(String(describing: cmd)) success: \(success)")
        reply(success ? 0 : 1)
    }
}
