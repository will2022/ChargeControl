import AppIntents
import Foundation

// --- Intents ---

struct GetStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Battery Status"
    static var description = IntentDescription("Returns current battery level, temperature, and power load.")

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let connection = NSXPCConnection(machServiceName: "com.chargecontrol.daemon")
        connection.remoteObjectInterface = NSXPCInterface(with: ChargeControlDaemonProtocol.self)
        connection.resume()
        
        let status: String = try await withCheckedThrowingContinuation { continuation in
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(throwing: error)
            } as? ChargeControlDaemonProtocol
            
            proxy?.getState { state in
                guard let s = state else {
                    continuation.resume(returning: "Error: Could not get state")
                    return
                }
                
                let level = s["percentage"] as? Int ?? 0
                let temp = s["batteryTemp"] as? Double ?? 0.0
                let load = s["systemPowerWatts"] as? Double ?? 0.0
                let result = "Battery: \(level)%, Temp: \(String(format: "%.1f", temp))°C, Load: \(String(format: "%.2f", load))W"
                
                continuation.resume(returning: result)
            }
        }
        return .result(value: status)
    }
}

struct SetLimitIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Charge Limit"
    
    @Parameter(title: "Maximum Limit", default: 80.0, controlStyle: .slider, inclusiveRange: (20.0, 100.0))
    var limit: Double

    func perform() async throws -> some IntentResult {
        let connection = NSXPCConnection(machServiceName: "com.chargecontrol.daemon")
        connection.remoteObjectInterface = NSXPCInterface(with: ChargeControlDaemonProtocol.self)
        connection.resume()
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(throwing: error)
            } as? ChargeControlDaemonProtocol
            
            proxy?.setSettings(settings: ["maxLimit": Int(limit)]) { res in
                continuation.resume(returning: ())
            }
        }
        return .result()
    }
}

struct PauseChargingIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Pause Charging"
    
    @Parameter(title: "Paused")
    var paused: Bool

    func perform() async throws -> some IntentResult {
        let connection = NSXPCConnection(machServiceName: "com.chargecontrol.daemon")
        connection.remoteObjectInterface = NSXPCInterface(with: ChargeControlDaemonProtocol.self)
        connection.resume()
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(throwing: error)
            } as? ChargeControlDaemonProtocol
            
            let cmd: ChargeControlCommand = paused ? .disableCharging : .chargeToLimit
            proxy?.execute(command: cmd.rawValue) { _ in
                continuation.resume(returning: ())
            }
        }
        return .result()
    }
}

struct ForceBatteryIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Force Battery Power"
    
    @Parameter(title: "Forced")
    var forced: Bool

    func perform() async throws -> some IntentResult {
        let connection = NSXPCConnection(machServiceName: "com.chargecontrol.daemon")
        connection.remoteObjectInterface = NSXPCInterface(with: ChargeControlDaemonProtocol.self)
        connection.resume()
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(throwing: error)
            } as? ChargeControlDaemonProtocol
            
            let cmd: ChargeControlCommand = forced ? .disablePowerAdapter : .enablePowerAdapter
            proxy?.execute(command: cmd.rawValue) { _ in
                continuation.resume(returning: ())
            }
        }
        return .result()
    }
}

struct TopUpIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Top Up Mode"
    
    @Parameter(title: "Active")
    var active: Bool

    func perform() async throws -> some IntentResult {
        let connection = NSXPCConnection(machServiceName: "com.chargecontrol.daemon")
        connection.remoteObjectInterface = NSXPCInterface(with: ChargeControlDaemonProtocol.self)
        connection.resume()
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(throwing: error)
            } as? ChargeControlDaemonProtocol
            
            let cmd: ChargeControlCommand = active ? .chargeToFull : .chargeToLimit
            proxy?.execute(command: cmd.rawValue) { _ in
                continuation.resume(returning: ())
            }
        }
        return .result()
    }
}

// --- Shortcut Provider ---

struct ChargeControlShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetStatusIntent(),
            phrases: [
                "Get \(.applicationName) status",
                "How is my battery in \(.applicationName)?"
            ],
            shortTitle: "Get Status",
            systemImageName: "battery.100"
        )
        
        AppShortcut(
            intent: TopUpIntent(),
            phrases: [
                "Start \(.applicationName) Top Up",
                "Stop \(.applicationName) Top Up"
            ],
            shortTitle: "Toggle Top Up",
            systemImageName: "bolt.fill"
        )
    }
}
