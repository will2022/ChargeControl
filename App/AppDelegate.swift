import Cocoa
import SwiftUI
import ServiceManagement
import os

let appLogger = Logger(subsystem: "com.chargecontrol.app", category: "App")

func logToFile(_ message: String) {
    let fileManager = FileManager.default
    guard let logsFolder = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first?.appendingPathComponent("Logs").appendingPathComponent("ChargeControl") else { return }
    
    if !fileManager.fileExists(atPath: logsFolder.path) {
        try? fileManager.createDirectory(at: logsFolder, withIntermediateDirectories: true)
    }
    
    let logPath = logsFolder.appendingPathComponent("app.log").path
    let timestamp = Date().description
    let logMessage = "[\(timestamp)] \(message)\n"
    
    if let data = logMessage.data(using: .utf8) {
        if let fileHandle = FileHandle(forWritingAtPath: logPath) {
            fileHandle.seekToEndOfFile()
            fileHandle.write(data)
            fileHandle.closeFile()
        } else {
            try? data.write(to: URL(fileURLWithPath: logPath))
        }
    }
}

@main
struct ChargeControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var battery = BatteryState()
    
    var body: some Scene {
        MenuBarExtra { [appDelegate] in
            // --- Critical Stats ---
            Section("Status") {
                Text("Level: \(battery.percentage)%")
                if let temp = battery.batteryTemp {
                    Text("Temp: \(String(format: "%.1f°C", temp))")
                }
                Text("Load: \(String(format: "%.2f W", battery.systemPowerWatts))")
                Text("Range: \(battery.startLimit)% - \(battery.maxLimit)%")
            }
            
            Divider()
            
            // --- Quick Actions ---
            Button(action: { appDelegate.executeCommand(battery.chargingDisabled ? .chargeToLimit : .disableCharging, battery: battery) }) {
                Label(battery.chargingDisabled ? "Resume Charging" : "Pause Charging", systemImage: battery.chargingDisabled ? "play.fill" : "pause.fill")
            }
            
            Button(action: { appDelegate.executeCommand(battery.adapterDisabled ? .enablePowerAdapter : .disablePowerAdapter, battery: battery) }) {
                Label(battery.adapterDisabled ? "Use Power Adapter" : "Force Battery Power", systemImage: battery.adapterDisabled ? "plug.fill" : "battery.100")
            }
            
            if battery.chargingToFull {
                Button(action: { appDelegate.executeCommand(.chargeToLimit, battery: battery) }) {
                    Label("Cancel Top Up", systemImage: "xmark.circle")
                }
            } else {
                Button(action: { appDelegate.executeCommand(.chargeToFull, battery: battery) }) {
                    Label("Top Up to 100%", systemImage: "bolt.fill")
                }
            }
            
            Divider()
            
            Button("Settings...") {
                appDelegate.showSettings(battery: battery)
            }
            
            Divider()
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        } label: {
            Image(nsImage: battery.icon)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var shared: AppDelegate?
    var settingsWindow: NSWindow?
    private var xpcConnection: NSXPCConnection?

    private func getXPCConnection() -> NSXPCConnection {
        if let conn = xpcConnection { return conn }
        let conn = NSXPCConnection(machServiceName: "com.chargecontrol.daemon")
        conn.remoteObjectInterface = NSXPCInterface(with: ChargeControlDaemonProtocol.self)
        conn.interruptionHandler = { [weak self] in
            appLogger.error("XPC Connection interrupted")
            self?.xpcConnection = nil
        }
        conn.invalidationHandler = { [weak self] in
            appLogger.error("XPC Connection invalidated")
            self?.xpcConnection = nil
        }
        conn.resume()
        self.xpcConnection = conn
        return conn
    }

    override init() {
        super.init()
        AppDelegate.shared = self
        logToFile("AppDelegate initialized")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let icon = NSImage(systemSymbolName: "bolt.batteryblock.fill", accessibilityDescription: nil) {
            NSApplication.shared.applicationIconImage = icon
        }
        appLogger.info("ChargeControl: applicationDidFinishLaunching called")
        logToFile("Application did finish launching")
        registerDaemon()
    }
    
    func showSettings(battery: BatteryState) {
        logToFile("showSettings called")
        if settingsWindow == nil {
            logToFile("Creating new settings window")
            let contentView = SettingsView(appDelegate: self, battery: battery)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 650, height: 450),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.center()
            window.setFrameAutosaveName("Settings")
            window.contentView = NSHostingView(rootView: contentView)
            window.makeKeyAndOrderFront(nil)
            settingsWindow = window
            NSApp.activate(ignoringOtherApps: true)
        } else {
            logToFile("Showing existing settings window")
            settingsWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    func registerDaemon() {
        let service = SMAppService.daemon(plistName: "com.chargecontrol.daemon.plist")
        do {
            try service.register()
            appLogger.info("Successfully registered daemon")
            logToFile("Successfully registered daemon")
        } catch {
            appLogger.error("Failed to register daemon: \(error.localizedDescription)")
            logToFile("Failed to register daemon: \(error.localizedDescription)")
        }
    }

    // --- Core Logic ---
    func executeCommand(_ command: ChargeControlCommand, battery: BatteryState) {
        logToFile("Executing command: \(command)")
        let proxy = getXPCConnection().remoteObjectProxyWithErrorHandler { error in
            appLogger.error("XPC Error executing command \(String(describing: command)): \(error.localizedDescription)")
            logToFile("XPC Error executing command \(command): \(error.localizedDescription)")
            DispatchQueue.main.async {
                battery.update() // Revert UI if failed
            }
        } as? ChargeControlDaemonProtocol
        
        proxy?.execute(command: command.rawValue, reply: { status in
            appLogger.info("Command \(String(describing: command)) result: \(status)")
            logToFile("Command \(command) result: \(status)")
            DispatchQueue.main.async {
                battery.update()
            }
        })
    }
    
    func applySettings(chargeLimit: Double, startLimit: Double, floatingMode: Bool, isAudioWarningEnabled: Bool, audioSoundName: String, autoDischarge: Bool, heatProtection: Bool, heatThreshold: Double, magSafeSync: Bool, sleepDuringCharge: Bool, sleepDuringDischarge: Bool, powerUserMode: Bool, battery: BatteryState) {
        logToFile("Applying settings: limit=\(chargeLimit), start=\(startLimit)")
        let proxy = getXPCConnection().remoteObjectProxyWithErrorHandler { error in
            appLogger.error("XPC Error applying settings: \(error.localizedDescription)")
            logToFile("XPC Error applying settings: \(error.localizedDescription)")
        } as? ChargeControlDaemonProtocol
        proxy?.setSettings(settings: [
            "maxLimit": Int(chargeLimit),
            "startLimit": Int(startLimit),
            "floatingMode": floatingMode,
            "audioWarningEnabled": isAudioWarningEnabled,
            "audioSoundName": audioSoundName,
            "autoDischarge": autoDischarge,
            "heatProtection": heatProtection,
            "heatThreshold": heatThreshold,
            "magSafeSync": magSafeSync,
            "sleepDuringCharge": sleepDuringCharge,
            "sleepDuringDischarge": sleepDuringDischarge,
            "powerUserMode": powerUserMode
        ], reply: { status in
            appLogger.info("Settings applied: \(status)")
            logToFile("Settings applied: \(status)")
            if status == 0 {
                DispatchQueue.main.async {
                    battery.maxLimit = Int(chargeLimit)
                    battery.startLimit = Int(startLimit)
                    battery.floatingMode = floatingMode
                    battery.isAudioWarningEnabled = isAudioWarningEnabled
                    battery.audioSoundName = audioSoundName
                    battery.autoDischarge = autoDischarge
                    battery.heatProtection = heatProtection
                    battery.heatThreshold = heatThreshold
                    battery.magSafeSync = magSafeSync
                    battery.sleepDuringCharge = sleepDuringCharge
                    battery.sleepDuringDischarge = sleepDuringDischarge
                    battery.powerUserMode = powerUserMode
                }
            }
        })
    }
}
