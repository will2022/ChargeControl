import Foundation

let connection = NSXPCConnection(machServiceName: "com.chargecontrol.daemon")
connection.remoteObjectInterface = NSXPCInterface(with: ChargeControlDaemonProtocol.self)
connection.resume()

guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
    print("Error: Could not connect to daemon (\(error.localizedDescription))")
    exit(1)
}) as? ChargeControlDaemonProtocol else {
    print("Error: Protocol mismatch")
    exit(1)
}

let args = CommandLine.arguments

func printUsage() {
    print("""
    ChargeControl CLI v1.0.0
    
    Usage: cc <command> [options]
    
    Commands:
      status        Show current battery and daemon status
      pause         Pause battery charging (Manual override)
      resume        Resume charging logic (Revert to limits)
      force         Force battery power (Virtual adapter disconnect)
      unforce       Reconnect virtual adapter
      topup         Start Top Up to 100%
      limit <n>     Set Max Charge Limit to <n>%
      help          Show this help
    """)
}

guard args.count > 1 else {
    printUsage()
    exit(0)
}

let command = args[1].lowercased()

switch command {
case "status":
    proxy.getState { state in
        guard let s = state else {
            print("Failed to get state")
            exit(1)
        }
        print("--- ChargeControl Status ---")
        print("Battery Level:    \(s["percentage"] ?? 0)%")
        print("Charging Paused:  \(s["chargingDisabled"] ?? false)")
        print("Forced Battery:   \(s["adapterDisabled"] ?? false)")
        print("Max Limit:        \(s["maxLimit"] ?? 0)%")
        print("Start Limit:      \(s["startLimit"] ?? 0)%")
        print("Top Up Active:    \(s["chargingToFull"] ?? false)")
        if let temp = s["batteryTemp"] as? Double {
            print("Temperature:      \(String(format: "%.1f", temp))°C")
        }
        exit(0)
    }
case "pause":
    proxy.execute(command: ChargeControlCommand.disableCharging.rawValue) { res in
        print(res == 0 ? "Charging paused." : "Failed to pause charging.")
        exit(res)
    }
case "resume":
    proxy.execute(command: ChargeControlCommand.chargeToLimit.rawValue) { res in
        print(res == 0 ? "Charging resumed (limits enforced)." : "Failed to resume charging.")
        exit(res)
    }
case "force":
    proxy.execute(command: ChargeControlCommand.disablePowerAdapter.rawValue) { res in
        print(res == 0 ? "Power adapter virtually disconnected." : "Failed to force battery power.")
        exit(res)
    }
case "unforce":
    proxy.execute(command: ChargeControlCommand.enablePowerAdapter.rawValue) { res in
        print(res == 0 ? "Power adapter virtually reconnected." : "Failed to reconnect adapter.")
        exit(res)
    }
case "topup":
    proxy.execute(command: ChargeControlCommand.chargeToFull.rawValue) { res in
        print(res == 0 ? "Top Up started." : "Failed to start Top Up.")
        exit(res)
    }
case "limit":
    guard args.count > 2, let limit = Int(args[2]) else {
        print("Error: Missing limit value")
        exit(1)
    }
    proxy.setSettings(settings: ["maxLimit": limit]) { res in
        print(res == 0 ? "Max limit set to \(limit)%." : "Failed to set limit.")
        exit(res)
    }
case "help", "--help", "-h":
    printUsage()
    exit(0)
default:
    print("Unknown command: \(command)")
    printUsage()
    exit(1)
}

RunLoop.main.run()
