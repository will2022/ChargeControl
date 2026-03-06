import Foundation

class ChargeControlDaemonDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        // Here we would ideally check the code signing of the connecting process.
        // For a minimal implementation, we will accept the connection.
        
        newConnection.exportedInterface = NSXPCInterface(with: ChargeControlDaemonProtocol.self)
        newConnection.exportedObject = ChargeControlDaemon.shared
        newConnection.resume()
        return true
    }
}

let delegate = ChargeControlDaemonDelegate()
let listener = NSXPCListener(machServiceName: "com.chargecontrol.daemon")
listener.delegate = delegate
listener.resume()

PowerMonitor.shared.startMonitoring()

RunLoop.main.run()
