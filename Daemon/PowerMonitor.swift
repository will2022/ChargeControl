import Foundation
import IOKit.ps
import os

let monitorLogger = Logger(subsystem: "com.chargecontrol.daemon", category: "PowerMonitor")

class PowerMonitor {
    static let shared = PowerMonitor()
    
    private let maxLimitKey = "maxLimit"
    private let startLimitKey = "startLimit"
    private let floatingModeKey = "floatingMode"
    private let audioWarningEnabledKey = "audioWarningEnabled"
    private let audioSoundNameKey = "audioSoundName"
    private let chargingDisabledManualKey = "chargingDisabledManual"
    private let adapterDisabledManualKey = "adapterDisabledManual"
    private let autoDischargeKey = "autoDischarge"
    private let heatProtectionKey = "heatProtection"
    private let heatThresholdKey = "heatThreshold"
    private let magSafeSyncKey = "magSafeSync"
    private let sleepDuringChargeKey = "sleepDuringCharge"
    private let sleepDuringDischargeKey = "sleepDuringDischarge"
    private let sleepAggressiveKey = "sleepAggressive"
    private let powerUserModeKey = "powerUserMode"
    
    private var runLoopSource: Unmanaged<CFRunLoopSource>?
    private var logTimer: Timer?
    private var watchdogTimer: Timer?
    private var maxLimit: Int
    private var startLimit: Int
    private var audioWarningEnabled: Bool
    var audioSoundName: String
    var chargingToFull: Bool = false
    
    var chargingDisabledManual: Bool
    var adapterDisabledManual: Bool
    
    var autoDischargeEnabled: Bool
    var floatingModeEnabled: Bool
    var heatProtectionEnabled: Bool
    var heatThreshold: Double
    var magSafeSyncEnabled: Bool
    var disableSleepDuringCharge: Bool
    var disableSleepDuringDischarge: Bool
    var disableSleepAggressive: Bool
    var powerUserModeEnabled: Bool
    
    private var currentSleepDisabled: Bool = false
    var isChargingEnabledState: Bool = false
    var isHeatProtectionTriggered: Bool = false

    private init() {
        let defaults = UserDefaults.standard
        self.maxLimit = defaults.integer(forKey: maxLimitKey) > 0 ? defaults.integer(forKey: maxLimitKey) : 80
        self.startLimit = defaults.integer(forKey: startLimitKey) > 0 ? defaults.integer(forKey: startLimitKey) : 75
        self.floatingModeEnabled = defaults.object(forKey: floatingModeKey) != nil ? defaults.bool(forKey: floatingModeKey) : true
        self.audioWarningEnabled = defaults.bool(forKey: audioWarningEnabledKey)
        self.audioSoundName = defaults.string(forKey: audioSoundNameKey) ?? "charging"
        self.chargingDisabledManual = defaults.bool(forKey: chargingDisabledManualKey)
        self.adapterDisabledManual = defaults.bool(forKey: adapterDisabledManualKey)
        
        self.autoDischargeEnabled = defaults.bool(forKey: autoDischargeKey)
        self.heatProtectionEnabled = defaults.object(forKey: heatProtectionKey) != nil ? defaults.bool(forKey: heatProtectionKey) : true
        self.heatThreshold = defaults.double(forKey: heatThresholdKey) > 0 ? defaults.double(forKey: heatThresholdKey) : 35.0
        self.magSafeSyncEnabled = defaults.object(forKey: magSafeSyncKey) != nil ? defaults.bool(forKey: magSafeSyncKey) : true
        self.disableSleepDuringCharge = defaults.object(forKey: sleepDuringChargeKey) != nil ? defaults.bool(forKey: sleepDuringChargeKey) : true
        self.disableSleepDuringDischarge = defaults.object(forKey: sleepDuringDischargeKey) != nil ? defaults.bool(forKey: sleepDuringDischargeKey) : true
        self.disableSleepAggressive = defaults.bool(forKey: sleepAggressiveKey)
        self.powerUserModeEnabled = defaults.bool(forKey: powerUserModeKey)
        
        PowerManagement.restore()
    }
    
    func startMonitoring() {
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        runLoopSource = IOPSNotificationCreateRunLoopSource({ (context) in
            guard let context = context else { return }
            let monitor = Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue()
            monitor.checkBatteryState()
        }, context)
        
        if let rls = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), rls.takeUnretainedValue(), .defaultMode)
            monitorLogger.info("Started monitoring battery state.")
            checkBatteryState()
        }

        // Start logging timer (every 60 seconds)
        logTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.performLogging()
        }
        logTimer?.tolerance = 30.0  // Allow macOS to coalesce timer wakes for deep sleep

        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 300.0, repeats: true) { [weak self] _ in
            self?.checkBatteryState()
        }
        watchdogTimer?.tolerance = 60.0
        
        // Start listening to system sleep/wake events
        SleepWakeHandler.shared.start()
    }
    
    private func performLogging() {
        // Skip logging when on battery with no active overrides — let the Mac sleep
        let adapterWatts = SMCComm.readFloat("PDTR") ?? 0
        let hasActiveOverride = chargingToFull || chargingDisabledManual || adapterDisabledManual
        if adapterWatts <= 0 && !hasActiveOverride {
            return
        }
        
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as Array
        
        for source in sources {
            if let desc = IOPSGetPowerSourceDescription(snapshot, source).takeUnretainedValue() as? [String: Any] {
                if let isPresent = desc[kIOPSIsPresentKey] as? Bool, isPresent,
                   let cap = desc[kIOPSCurrentCapacityKey] as? Int {
                    
                    let volt = Double(SMCComm.readUInt16LE("B0AV") ?? 0) / 1000.0
                    let sysWatts = Double(SMCComm.readFloat("PSTR") ?? 0)
                    let adapterWatts = Double(SMCComm.readFloat("PDTR") ?? 0)
                    
                    // Battery Flow: Adapter Input minus System Load
                    // If result is positive, we are charging. If negative, we are discharging.
                    let battWatts = adapterWatts - sysWatts
                    
                    let temp = SMCComm.readTemperature("B0Te") ?? 0.0
                    
                    Database.shared.logStats(
                        percentage: cap,
                        voltage: volt,
                        amperage: 0, // Amperage is less useful than Watts here
                        systemPower: sysWatts,
                        batteryPower: battWatts,
                        temp: temp
                    )
                    break
                }
            }
        }
    }
    
    func stopMonitoring() {
        logTimer?.invalidate()
        logTimer = nil
        watchdogTimer?.invalidate()
        watchdogTimer = nil
        if let rls = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), rls.takeUnretainedValue(), .defaultMode)
            runLoopSource = nil
        }
    }
    
    func setMaxLimit(_ limit: Int) {
        maxLimit = limit
        UserDefaults.standard.set(limit, forKey: maxLimitKey)
        UserDefaults.standard.synchronize()
        checkBatteryState()
        SMCComm.cycleAdapter()
    }
    
    func setStartLimit(_ limit: Int) {
        startLimit = limit
        UserDefaults.standard.set(limit, forKey: startLimitKey)
        UserDefaults.standard.synchronize()
        checkBatteryState()
    }

    func setFloatingMode(_ enabled: Bool) {
        floatingModeEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: floatingModeKey)
        UserDefaults.standard.synchronize()
        checkBatteryState()
    }
    
    func getMaxLimit() -> Int { return maxLimit }
    func getStartLimit() -> Int { return startLimit }

    func setAudioWarningEnabled(_ enabled: Bool) {
        audioWarningEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: audioWarningEnabledKey)
        UserDefaults.standard.synchronize()
    }

    func setAudioSoundName(_ name: String) {
        audioSoundName = name
        UserDefaults.standard.set(name, forKey: audioSoundNameKey)
        UserDefaults.standard.synchronize()
    }

    func isAudioWarningEnabled() -> Bool {
        return audioWarningEnabled
    }

    func setChargingDisabledManual(_ disabled: Bool) {
        chargingDisabledManual = disabled
        UserDefaults.standard.set(disabled, forKey: chargingDisabledManualKey)
        UserDefaults.standard.synchronize()
        checkBatteryState()
    }

    func setAdapterDisabledManual(_ disabled: Bool) {
        adapterDisabledManual = disabled
        UserDefaults.standard.set(disabled, forKey: adapterDisabledManualKey)
        UserDefaults.standard.synchronize()
        checkBatteryState()
    }

    func setAutoDischarge(_ enabled: Bool) {
        autoDischargeEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: autoDischargeKey)
        UserDefaults.standard.synchronize()
        checkBatteryState()
    }

    func setHeatProtection(_ enabled: Bool, threshold: Double) {
        heatProtectionEnabled = enabled
        heatThreshold = threshold
        UserDefaults.standard.set(enabled, forKey: heatProtectionKey)
        UserDefaults.standard.set(threshold, forKey: heatThresholdKey)
        UserDefaults.standard.synchronize()
        checkBatteryState()
    }

    func setMagSafeSync(_ enabled: Bool) {
        magSafeSyncEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: magSafeSyncKey)
        UserDefaults.standard.synchronize()
        if !enabled {
            _ = SMCComm.setMagSafeColor(.system)
        }
        checkBatteryState()
    }

    func setSleepSettings(disableDuringCharge: Bool, disableDuringDischarge: Bool, aggressive: Bool) {
        self.disableSleepDuringCharge = disableDuringCharge
        self.disableSleepDuringDischarge = disableDuringDischarge
        self.disableSleepAggressive = aggressive
        UserDefaults.standard.set(disableDuringCharge, forKey: sleepDuringChargeKey)
        UserDefaults.standard.set(disableDuringDischarge, forKey: sleepDuringDischargeKey)
        UserDefaults.standard.set(aggressive, forKey: sleepAggressiveKey)
        UserDefaults.standard.synchronize()
        checkBatteryState()
    }

    func setPowerUserMode(_ enabled: Bool) {
        powerUserModeEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: powerUserModeKey)
        UserDefaults.standard.synchronize()
        checkBatteryState()
    }
    
    private func updateSleepAssertion(isCharging: Bool, isDischarging: Bool) {
        let adapterWatts = SMCComm.readFloat("PDTR") ?? 0
        let isPhysicallyConnected = adapterWatts > 0.0 || isCharging
        
        let shouldInhibit = isPhysicallyConnected && (chargingToFull ||
                           (isCharging && disableSleepDuringCharge) ||
                           (isDischarging && disableSleepDuringDischarge))
        
        if shouldInhibit != currentSleepDisabled {
            PowerManagement.setSleepDisabled(shouldInhibit, aggressive: disableSleepAggressive)
            currentSleepDisabled = shouldInhibit
        } else if shouldInhibit && currentSleepDisabled {
            // Re-apply if settings changed (e.g. switching between aggressive and standard)
            PowerManagement.setSleepDisabled(true, aggressive: disableSleepAggressive)
        }
    }
    
    private func updateMagSafeLED(chargingDisabled: Bool, isManualDischarge: Bool) {
        guard magSafeSyncEnabled else {
            _ = SMCComm.setMagSafeColor(.system)
            return
        }
        
        if heatProtectionEnabled, let temp = SMCComm.readTemperature("B0Te"), temp >= heatThreshold {
            _ = SMCComm.setMagSafeColor(.orangeFastBlink)
            return
        }
        
        if isManualDischarge {
            _ = SMCComm.setMagSafeColor(.off)
            return
        }
        
        if chargingDisabled {
            _ = SMCComm.setMagSafeColor(.green)
        } else {
            _ = SMCComm.setMagSafeColor(.orange)
        }
    }
    
    @objc func checkBatteryState() {
        // 1. Heat Protection (Highest Priority)
        if heatProtectionEnabled, let currentTemp = SMCComm.readTemperature("B0Te") {
            if currentTemp >= heatThreshold {
                monitorLogger.warning("Heat protection active (\(currentTemp)°C). Disabling charging.")
                isHeatProtectionTriggered = true
                _ = SMCComm.writeKey("CH0C", value: [0x01])
                _ = SMCComm.writeKey("CHTE", value: [0x01, 0x00, 0x00, 0x00])
                updateMagSafeLED(chargingDisabled: true, isManualDischarge: false)
                updateSleepAssertion(isCharging: false, isDischarging: false)
                return
            }
        }
        isHeatProtectionTriggered = false

        // 2. Charge to Full
        if chargingToFull {
            monitorLogger.info("Charge to full active.")
            _ = SMCComm.writeKey("CH0C", value: [0x00])
            _ = SMCComm.writeKey("CHTE", value: [0x00, 0x00, 0x00, 0x00])
            _ = SMCComm.writeKey("CHIE", value: [0x00])
            _ = SMCComm.writeKey("CH0J", value: [0x00])
            updateMagSafeLED(chargingDisabled: false, isManualDischarge: false)
            updateSleepAssertion(isCharging: true, isDischarging: false)
            return
        }

        // 3. Manual Overrides
        if adapterDisabledManual {
            monitorLogger.info("Manual adapter disable active.")
            _ = SMCComm.writeKey("CH0C", value: [0x01])
            _ = SMCComm.writeKey("CHTE", value: [0x01, 0x00, 0x00, 0x00])
            _ = SMCComm.writeKey("CHIE", value: [0x08])
            _ = SMCComm.writeKey("CH0J", value: [0x20])
            updateMagSafeLED(chargingDisabled: true, isManualDischarge: true)
            updateSleepAssertion(isCharging: false, isDischarging: true)
            return
        }

        if chargingDisabledManual {
            monitorLogger.info("Manual charging disable active.")
            _ = SMCComm.writeKey("CH0C", value: [0x01])
            _ = SMCComm.writeKey("CHTE", value: [0x01, 0x00, 0x00, 0x00])
            _ = SMCComm.writeKey("CHIE", value: [0x00])
            _ = SMCComm.writeKey("CH0J", value: [0x00])
            updateMagSafeLED(chargingDisabled: true, isManualDischarge: false)
            updateSleepAssertion(isCharging: false, isDischarging: false)
            return
        }

        // 4. Automatic Logic
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as Array
        
        for source in sources {
            if let desc = IOPSGetPowerSourceDescription(snapshot, source).takeUnretainedValue() as? [String: Any] {
                if let isPresent = desc[kIOPSIsPresentKey] as? Bool, isPresent,
                   let cap = desc[kIOPSCurrentCapacityKey] as? Int,
                   let isCharging = desc[kIOPSIsChargingKey] as? Bool {
                    
                    monitorLogger.debug("Capacity: \(cap)%, Charging: \(isCharging)")
                    
                    // Enforce Start/Max Limits
                    let wasChargingEnabled = isChargingEnabledState
                    if cap >= maxLimit {
                        isChargingEnabledState = false
                    } else if cap < startLimit {
                        isChargingEnabledState = true
                    }

                    if !isChargingEnabledState {
                        // Check if macOS overrode our setting
                        if let currentCH0C = SMCComm.readKey("CH0C"), currentCH0C.first == 0x00 {
                            monitorLogger.warning("macOS override detected! CH0C was 00 (enabled), forcing back to 01 (inhibited).")
                        } else {
                            monitorLogger.info("Inhibiting charge.")
                        }

                        _ = SMCComm.writeKey("CH0C", value: [0x01])
                        _ = SMCComm.writeKey("CHTE", value: [0x01, 0x00, 0x00, 0x00])
                        
                        var isDischarging = false
                        if floatingModeEnabled || (autoDischargeEnabled && cap > maxLimit) {
                            monitorLogger.info("Floating or Auto-discharge active. Isolating adapter.")
                            _ = SMCComm.writeKey("CHIE", value: [0x08])
                            _ = SMCComm.writeKey("CH0J", value: [0x20])
                            isDischarging = true
                        } else {
                            _ = SMCComm.writeKey("CHIE", value: [0x00])
                            _ = SMCComm.writeKey("CH0J", value: [0x00])
                        }
                        
                        updateMagSafeLED(chargingDisabled: true, isManualDischarge: isDischarging)
                        updateSleepAssertion(isCharging: false, isDischarging: isDischarging)
                    } else {
                        monitorLogger.info("Allowing charge.")
                        _ = SMCComm.writeKey("CH0C", value: [0x00])
                        _ = SMCComm.writeKey("CHTE", value: [0x00, 0x00, 0x00, 0x00])
                        _ = SMCComm.writeKey("CHIE", value: [0x00])
                        _ = SMCComm.writeKey("CH0J", value: [0x00])
                        
                        // Cycle adapter on transition from inhibited → allowed
                        // macOS won't re-engage charging without a physical adapter power cycle
                        if !wasChargingEnabled {
                            monitorLogger.info("State transition: inhibit → allow. Cycling adapter.")
                            SMCComm.cycleAdapter()
                        }
                        
                        updateMagSafeLED(chargingDisabled: false, isManualDischarge: false)
                        updateSleepAssertion(isCharging: true, isDischarging: false)
                    }
                }
            }
        }
    }
}
