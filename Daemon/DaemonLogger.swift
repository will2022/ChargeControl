import Foundation

class DaemonLogger {
    static let shared = DaemonLogger()
    private let logPath = "/Library/Logs/ChargeControl/daemon.log"
    private let folderPath = "/Library/Logs/ChargeControl"
    private let queue = DispatchQueue(label: "com.chargecontrol.daemon.logger")
    
    private init() {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: folderPath) {
            try? fileManager.createDirectory(atPath: folderPath, withIntermediateDirectories: true)
        }
    }
    
    func log(_ message: String) {
        queue.async {
            let timestamp = Date().description
            let logMessage = "[\(timestamp)] \(message)\n"
            
            if let data = logMessage.data(using: .utf8) {
                if let fileHandle = FileHandle(forWritingAtPath: self.logPath) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                } else {
                    try? data.write(to: URL(fileURLWithPath: self.logPath))
                }
            }
            
            // Still log to system log as fallback
            print("ChargeControlDaemon: \(message)")
        }
    }
}
