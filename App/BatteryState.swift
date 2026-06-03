import Foundation
import SwiftUI
import IOKit.ps
import AVFoundation

struct BatteryHistoryItem: Identifiable {
    let id = UUID()
    let date: Date
    let percentage: Int
    let powerWatts: Double
    let systemPowerWatts: Double
}

struct ProcessEnergyInfo: Identifiable {
    let id: String // PID or Name
    let name: String
    let energyImpact: Double
    let icon: NSImage?
}

class BatteryState: ObservableObject {
    @Published var percentage: Int = 100
    @Published var isPluggedIn: Bool = false
    @Published var isCharging: Bool = false
    @Published var icon: NSImage = NSImage()
    @Published var chargingDisabled: Bool = false
    @Published var adapterDisabled: Bool = false
    @Published var maxLimit: Int = 80
    @Published var isAudioWarningEnabled: Bool = false
    @Published var audioSoundName: String = "charging"
    @Published var chargingToFull: Bool = false
    
    @Published var autoDischarge: Bool = false
    @Published var floatingMode: Bool = true
    @Published var startLimit: Int = 75
    @Published var heatProtection: Bool = true
    @Published var heatThreshold: Double = 35.0
    @Published var heatProtectionTriggered: Bool = false
    @Published var magSafeSync: Bool = true
    @Published var sleepDuringCharge: Bool = true
    @Published var sleepDuringDischarge: Bool = true
    @Published var disableSleepAggressive: Bool = false
    @Published var powerUserMode: Bool = false
    @Published var batteryTemp: Double? = nil
    @Published var temperatures: [String: Double] = [:]

    // --- Advanced Stats ---
    // Capacity & Health
    @Published var rawCurrentCapacity: Int = 0
    @Published var rawMaxCapacity: Int = 0
    @Published var designCapacity: Int = 0
    @Published var nominalCapacity: Int = 0
    @Published var cycleCount: Int = 0
    @Published var health: Double = 0.0
    
    // Real-time Power
    @Published var voltage: Double = 0.0
    @Published var amperage: Int = 0
    @Published var powerWatts: Double = 0.0
    @Published var systemPowerWatts: Double = 0.0
    
    // Hardware Info
    @Published var batterySerial: String = "--"
    @Published var batteryModel: String = "--"
    @Published var manufacturer: String = "--"
    
    // Adapter Info
    @Published var adapterWatts: Int = 0
    @Published var adapterDescription: String = "--"
    
    @Published var history: [BatteryHistoryItem] = []
    @Published var energyConsumers: [ProcessEnergyInfo] = []
    @Published var historicalEnergyConsumers: [ProcessEnergyInfo] = []
    @Published var energyError: String? = nil
    @Published var lastEnergyUpdate: Date = .distantPast
    
    private var lastHistoryFetch: Date = .distantPast
    private var iconCache: [String: NSImage] = [:]
    
    private var sound: NSSound?
    private var runLoopSource: Unmanaged<CFRunLoopSource>?
    private var refreshTimer: Timer?
    private var xpcConnection: NSXPCConnection?
    
    // Caching for energy optimization
    private var lastIconState: (Int, Bool, Bool)? = nil
    private var lastIcon: NSImage? = nil

    private func getXPCConnection() -> NSXPCConnection {
        if let conn = xpcConnection { return conn }
        let conn = NSXPCConnection(machServiceName: "com.chargecontrol.daemon")
        conn.remoteObjectInterface = NSXPCInterface(with: ChargeControlDaemonProtocol.self)
        conn.interruptionHandler = { [weak self] in
            self?.xpcConnection = nil
        }
        conn.invalidationHandler = { [weak self] in
            self?.xpcConnection = nil
        }
        conn.resume()
        self.xpcConnection = conn
        return conn
    }
    
    init() {
        update()
        startMonitoring()
        
        // Polling interval increased from 2.0s to 10.0s for energy efficiency.
        // IOPSNotification handles immediate updates for percentage/charging state changes.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.update()
        }
        refreshTimer?.tolerance = 2.0  // Allow significant coalescence for power efficiency
    }
    
    func startMonitoring() {
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        runLoopSource = IOPSNotificationCreateRunLoopSource({ (context) in
            guard let context = context else { return }
            let state = Unmanaged<BatteryState>.fromOpaque(context).takeUnretainedValue()
            state.update()
        }, context)
        
        if let rls = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), rls.takeUnretainedValue(), .defaultMode)
        }
    }
    
    func update() {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as Array
        
        for source in sources {
            if let desc = IOPSGetPowerSourceDescription(snapshot, source).takeUnretainedValue() as? [String: Any] {
                if let isPresent = desc[kIOPSIsPresentKey] as? Bool, isPresent,
                   let currentCapacity = desc[kIOPSCurrentCapacityKey] as? Int,
                   let powerSourceState = desc[kIOPSPowerSourceStateKey] as? String,
                   let charging = desc[kIOPSIsChargingKey] as? Bool {
                    
                    let transitionToCharging = !self.isCharging && charging
                    
                    DispatchQueue.main.async {
                        self.percentage = currentCapacity
                        self.isPluggedIn = (powerSourceState == kIOPSACPowerValue)
                        self.isCharging = charging
                        
                        // Optimized: Only redraw icon if state actually changed
                        if self.lastIconState?.0 != currentCapacity || 
                           self.lastIconState?.1 != self.isPluggedIn || 
                           self.lastIconState?.2 != charging || 
                           self.lastIcon == nil {
                            let newIcon = self.drawBatteryIcon(percentage: currentCapacity, isPluggedIn: self.isPluggedIn, isCharging: self.isCharging)
                            self.icon = newIcon
                            self.lastIcon = newIcon
                            self.lastIconState = (currentCapacity, self.isPluggedIn, charging)
                        }
                        
                        if transitionToCharging && self.isAudioWarningEnabled {
                            self.playWarningSound()
                        }
                    }
                    break
                }
            }
        }
        
        // 2-minute cadence for less critical stats is handled by the daemon logic now.
        // We removed the ioreg process spawning here to save battery.
        
        // Fetch state from daemon for ALL telemetry
        let proxy = getXPCConnection().remoteObjectProxyWithErrorHandler { error in
            appLogger.error("XPC Error getting state: \(error.localizedDescription)")
        } as? ChargeControlDaemonProtocol
        
        proxy?.getState(reply: { state in
            if let state = state {
                DispatchQueue.main.async {
                    self.chargingDisabled = state["chargingDisabled"] as? Bool ?? false
                    self.adapterDisabled = state["adapterDisabled"] as? Bool ?? false
                    
                    if let limit = state["maxLimit"] as? Int { self.maxLimit = limit }
                    if let start = state["startLimit"] as? Int { self.startLimit = start }
                    if let audioEnabled = state["audioWarningEnabled"] as? Bool { self.isAudioWarningEnabled = audioEnabled }
                    if let audioSoundName = state["audioSoundName"] as? String { self.audioSoundName = audioSoundName }
                    if let chargingToFull = state["chargingToFull"] as? Bool { self.chargingToFull = chargingToFull }
                    if let autoDischarge = state["autoDischarge"] as? Bool { self.autoDischarge = autoDischarge }
                    if let floatingMode = state["floatingMode"] as? Bool { self.floatingMode = floatingMode }
                    if let heatProtection = state["heatProtection"] as? Bool { self.heatProtection = heatProtection }
                    if let heatThreshold = state["heatThreshold"] as? Double { self.heatThreshold = heatThreshold }
                    if let heatTriggered = state["heatProtectionTriggered"] as? Bool { self.heatProtectionTriggered = heatTriggered }
                    if let magSafeSync = state["magSafeSync"] as? Bool { self.magSafeSync = magSafeSync }
                    if let sleepCharge = state["sleepDuringCharge"] as? Bool { self.sleepDuringCharge = sleepCharge }
                    if let sleepDischarge = state["sleepDuringDischarge"] as? Bool { self.sleepDuringDischarge = sleepDischarge }
                    if let sleepAggressive = state["sleepAggressive"] as? Bool { self.disableSleepAggressive = sleepAggressive }
                    if let powerUser = state["powerUserMode"] as? Bool { self.powerUserMode = powerUser }

                    // Mapping from consolidated Daemon Telemetry
                    if let serial = state["batterySerial"] as? String { self.batterySerial = serial }
                    if let model = state["batteryModel"] as? String { self.batteryModel = model }
                    if let cap = state["nominalCapacity"] as? Int { self.nominalCapacity = cap }
                    if let dCap = state["designCapacity"] as? Int { self.designCapacity = dCap }
                    if let rawMax = state["rawMaxCapacity"] as? Int { self.rawMaxCapacity = rawMax }
                    if let rawCur = state["rawCurrentCapacity"] as? Int { self.rawCurrentCapacity = rawCur }
                    if let watts = state["adapterWatts"] as? Int { self.adapterWatts = watts }
                    if let desc = state["adapterDescription"] as? String { self.adapterDescription = desc }
                    
                    if let temp = state["batteryTemp"] as? Double { self.batteryTemp = temp }
                    if let ioregTemp = state["ioregTemp"] as? Double {
                        if self.batteryTemp == nil || self.batteryTemp == 0 { self.batteryTemp = ioregTemp }
                    }
                    
                    if let temps = state["temperatures"] as? [String: Double] { self.temperatures = temps }
                    if let amp = state["amperage"] as? Int { self.amperage = amp }
                    if let volt = state["voltage"] as? Double { self.voltage = volt }
                    if let sysPower = state["systemPowerWatts"] as? Double { self.systemPowerWatts = sysPower }
                    if let battWatts = state["batteryPowerWatts"] as? Double { self.powerWatts = battWatts }
                    if let cycles = state["cycleCount"] as? Int { self.cycleCount = cycles }
                    
                    // Prioritize SMC-based telemetry if available
                    self.powerWatts = (self.voltage * Double(self.amperage)) / 1000.0
                    if self.designCapacity > 0 {
                        self.health = (Double(self.rawMaxCapacity) / Double(self.designCapacity)) * 100.0
                    }
                }
            }
        })
        
        // Rate-limited logic for History & Analytics
        let now = Date()
        if now.timeIntervalSince(lastHistoryFetch) > 60 {
            fetchHistory()
            fetchHistoricalEnergyImpact()
            lastHistoryFetch = now
        }
        
        // Fetch Energy Impact Diagnostic Dictionary
        proxy?.getEnergyImpact(reply: { dict in
            guard let dict = dict else { return }
            
            let consumersData = dict["consumers"] as? [[String: Any]] ?? []
            let error = dict["error"] as? String
            let timestamp = dict["lastUpdate"] as? Date ?? .distantPast
            
            let consumers = consumersData.compactMap { item -> ProcessEnergyInfo? in
                guard let name = item["name"] as? String,
                      let pid = item["pid"] as? Int,
                      let impact = item["energy_impact"] as? Double else { return nil }
                
                let icon = self.getIconForProcess(pid: pid, name: name)
                return ProcessEnergyInfo(id: "\(pid)", name: name, energyImpact: impact, icon: icon)
            }
            
            DispatchQueue.main.async {
                self.energyConsumers = consumers
                self.energyError = error
                self.lastEnergyUpdate = timestamp
            }
        })
    }
    
    func fetchHistoricalEnergyImpact() {
        let proxy = getXPCConnection().remoteObjectProxyWithErrorHandler { error in
            appLogger.error("XPC Error fetching historical energy impact: \(error.localizedDescription)")
        } as? ChargeControlDaemonProtocol
        
        proxy?.getHistoricalEnergyImpact(reply: { dict in
            guard let dict = dict else { return }
            
            let consumersData = dict["consumers"] as? [[String: Any]] ?? []
            
            let consumers = consumersData.compactMap { item -> ProcessEnergyInfo? in
                guard let name = item["name"] as? String,
                      let impact = item["energy_impact"] as? Double else { return nil }
                
                let icon = self.getIconForProcess(pid: 0, name: name)
                return ProcessEnergyInfo(id: name, name: name, energyImpact: impact, icon: icon)
            }
            
            DispatchQueue.main.async {
                self.historicalEnergyConsumers = consumers
            }
        })
    }
    
    private func getIconForProcess(pid: Int, name: String) -> NSImage? {
        let cacheKey = pid > 0 ? "\(pid)" : name
        if let cached = iconCache[cacheKey] { return cached }
        
        var finalIcon: NSImage? = nil
        
        // 1. Primary: Try via PID
        if let app = NSRunningApplication(processIdentifier: pid_t(pid)) {
            finalIcon = app.icon
        }
        
        // 2. Fallback: try to find by name/ID in /Applications
        if finalIcon == nil {
            let workspace = NSWorkspace.shared
            if let url = workspace.urlForApplication(withBundleIdentifier: "com.apple.\(name)") ?? 
                         workspace.urlForApplication(withBundleIdentifier: name) {
                finalIcon = workspace.icon(forFile: url.path)
            }
        }
        
        // 3. Fallback: Common system processes or internal icons
        if finalIcon == nil {
            let lowerName = name.lowercased()
            if lowerName.contains("kernel") || lowerName.contains("windowserver") || lowerName == "launchd" || lowerName.contains("daemon") {
                finalIcon = NSImage(systemSymbolName: "cpu", accessibilityDescription: "System Process")
            } else if lowerName.contains("chrome") {
                finalIcon = NSImage(systemSymbolName: "globe", accessibilityDescription: "Web Browser")
            } else if lowerName.contains("safari") {
                finalIcon = NSImage(systemSymbolName: "safari", accessibilityDescription: "Web Browser")
            }
        }
        
        if let foundIcon = finalIcon {
            iconCache[cacheKey] = foundIcon
        }
        
        return finalIcon
    }
    
    private func fetchHistory() {
        let proxy = getXPCConnection().remoteObjectProxyWithErrorHandler { error in
            appLogger.error("XPC Error getting history: \(error.localizedDescription)")
        } as? ChargeControlDaemonProtocol
        
        proxy?.getHistory(reply: { results in
            guard let results = results else { return }
            
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd HH:mm:ss"
            
            let items = results.compactMap { dict -> BatteryHistoryItem? in
                guard let ts = dict["timestamp"] as? String,
                      let date = df.date(from: ts),
                      let perc = dict["percentage"] as? Int,
                      let pWatts = dict["battery_power"] as? Double,
                      let sWatts = dict["system_power"] as? Double else { return nil }
                
                return BatteryHistoryItem(date: date, percentage: perc, powerWatts: pWatts, systemPowerWatts: sWatts)
            }
            
            DispatchQueue.main.async {
                self.history = items.reversed() // Order chronologically for charts
            }
        })
    }
    
    private func parseIoreg(_ output: String) {
        let lines = output.components(separatedBy: .newlines)
        DispatchQueue.main.async {
            for line in lines {
                let parts = line.split(separator: "=")
                guard parts.count >= 2 else { continue }
                let key = parts[0].trimmingCharacters(in: CharacterSet(charactersIn: " \""))
                let val = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: " \""))
                
                switch key {
                case "CycleCount": self.cycleCount = Int(val) ?? self.cycleCount
                case "DesignCapacity": self.designCapacity = Int(val) ?? self.designCapacity
                case "AppleRawMaxCapacity": self.rawMaxCapacity = Int(val) ?? self.rawMaxCapacity
                case "NominalChargeCapacity": self.nominalCapacity = Int(val) ?? self.nominalCapacity
                case "AppleRawCurrentCapacity": self.rawCurrentCapacity = Int(val) ?? self.rawCurrentCapacity
                case "Voltage": self.voltage = (Double(val) ?? (self.voltage * 1000.0)) / 1000.0
                case "Temperature": if self.batteryTemp == nil { self.batteryTemp = (Double(val) ?? 0) / 100.0 }
                case "Serial": self.batterySerial = val
                case "DeviceName": self.batteryModel = val
                case "Amperage":
                    // ioreg Amperage can be huge unsigned if negative
                    if let rawAmp = UInt64(val) {
                        if rawAmp > 0x7FFFFFFFFFFFFFFF {
                            self.amperage = Int(Int64(bitPattern: rawAmp))
                        } else {
                            self.amperage = Int(rawAmp)
                        }
                    }
                default: break
                }
                
                // Parse nested AdapterDetails
                if line.contains("\"Watts\" = "), let w = Int(val) { self.adapterWatts = w }
                if line.contains("\"Description\" = ") { self.adapterDescription = val }
            }
            
            // Recalculate health
            if self.designCapacity > 0 {
                self.health = (Double(self.rawMaxCapacity) / Double(self.designCapacity)) * 100.0
            }
            self.powerWatts = (self.voltage * Double(self.amperage)) / 1000.0
        }
    }
    
    func testSound() {
        logToFile("Testing sound...")
        playWarningSound()
    }
    
    func playWarningSound() {
        sound = NSSound(named: NSSound.Name(audioSoundName))
        if let sound = sound {
            sound.play()
            logToFile("Playing charging warning sound: \(audioSoundName)")
        } else {
            logToFile("Failed to load sound: \(audioSoundName)")
        }
    }
    
    private func drawBatteryIcon(percentage: Int, isPluggedIn: Bool, isCharging: Bool) -> NSImage {
        let width: CGFloat = 33
        let height: CGFloat = 14
        let img = NSImage(size: NSSize(width: width, height: height))
        
        img.lockFocus()
        
        // 1. Draw solid battery body
        let bodyRect = NSRect(x: 0.5, y: 0.5, width: width - 4, height: height - 1)
        let bodyPath = NSBezierPath(roundedRect: bodyRect, xRadius: 3, yRadius: 3)
        NSColor.labelColor.setFill()
        bodyPath.fill()
        
        // 2. Draw battery tip
        let tipRect = NSRect(x: width - 3, y: height / 2 - 2.5, width: 2, height: 5)
        let tipPath = NSBezierPath(roundedRect: tipRect, xRadius: 1, yRadius: 1)
        NSColor.labelColor.setFill()
        tipPath.fill()
        
        // 3. Draw content (Percentage and optionally Plug/Bolt)
        let text = "\(percentage)"
        let fontSize: CGFloat = 10
        let font = NSFont.systemFont(ofSize: fontSize, weight: .heavy)
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]
        
        let textSize = text.size(withAttributes: attributes)
        let capHeight = font.capHeight
        let yOffset = (bodyRect.height - capHeight) / 2 + font.descender
        
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        
        if isPluggedIn {
            let iconWidth: CGFloat = 8
            let spacing: CGFloat = 1
            let totalContentWidth = iconWidth + spacing + textSize.width
            
            let startX = bodyRect.origin.x + (bodyRect.width - totalContentWidth) / 2
            let centerY = bodyRect.origin.y + bodyRect.height / 2
            
            if isCharging {
                // Draw Lightning Bolt
                let boltPath = NSBezierPath()
                boltPath.move(to: NSPoint(x: startX + 5.0, y: centerY + 4.0)) 
                boltPath.line(to: NSPoint(x: startX + 2.0, y: centerY + 0.5)) 
                boltPath.line(to: NSPoint(x: startX + 4.5, y: centerY + 0.5)) 
                boltPath.line(to: NSPoint(x: startX + 3.0, y: centerY - 4.0)) 
                boltPath.line(to: NSPoint(x: startX + 6.0, y: centerY - 0.5)) 
                boltPath.line(to: NSPoint(x: startX + 3.5, y: centerY - 0.5)) 
                boltPath.close()

                // Smooth corners
                boltPath.lineJoinStyle = .round
                boltPath.lineWidth = 0.5 

                // Fill and stroke
                boltPath.fill()
                boltPath.stroke()
            } else {
                // Draw Vertical Plug
                let plugWidth: CGFloat = 7
                // 1. Cord (bottom)
                let cordRect = NSRect(x: startX + (plugWidth - 1) / 2, y: centerY - 5, width: 1, height: 2)
                NSBezierPath(rect: cordRect).fill()

                // 2. Plug Body
                let plugBodyRect = NSRect(x: startX, y: centerY - 3, width: plugWidth, height: 5)
                NSBezierPath(roundedRect: plugBodyRect, xRadius: 1, yRadius: 1).fill()
                
                // 3. Prongs (top)
                let prong1 = NSRect(x: startX + 1.5, y: centerY + 2, width: 1, height: 2.5)
                let prong2 = NSRect(x: startX + plugWidth - 2.5, y: centerY + 2, width: 1, height: 2.5)
                NSBezierPath(rect: prong1).fill()
                NSBezierPath(rect: prong2).fill()
            }
            
            // Draw Percentage text to the right
            let textRect = NSRect(
                x: startX + iconWidth + spacing,
                y: bodyRect.origin.y + yOffset - 0.5,
                width: textSize.width,
                height: textSize.height
            )
            text.draw(in: textRect, withAttributes: attributes)
        } else {
            let textRect = NSRect(
                x: bodyRect.origin.x + (bodyRect.width - textSize.width) / 2,
                y: bodyRect.origin.y + yOffset - 0.5,
                width: textSize.width,
                height: textSize.height
            )
            text.draw(in: textRect, withAttributes: attributes)
        }
        
        img.unlockFocus()
        img.isTemplate = true
        
        return img
    }
}
