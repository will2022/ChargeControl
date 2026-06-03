import Foundation
import os

let energyLogger = Logger(subsystem: "com.chargecontrol.daemon", category: "EnergyMonitor")

class EnergyMonitor {
    static let shared = EnergyMonitor()
    
    private var lastEnergyData: [[String: Any]] = []
    private var lastUpdate: Date = .distantPast
    private var lastError: String? = nil
    private let sampleInterval: TimeInterval = 60.0
    private var isRefreshing = false
    private var backgroundTimer: DispatchSourceTimer?
    
    private init() {
        startBackgroundTimer()
    }
    
    private func startBackgroundTimer() {
        backgroundTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .background))
        backgroundTimer?.schedule(deadline: .now() + 900, repeating: 900) // Every 15 minutes
        backgroundTimer?.setEventHandler { [weak self] in
            DaemonLogger.shared.log("EnergyMonitor: Triggering background sample.")
            self?.refreshData()
        }
        backgroundTimer?.resume()
    }
    
    func getDiagnosticState() -> [String: Any] {
        return [
            "consumers": lastEnergyData,
            "lastUpdate": lastUpdate,
            "error": lastError as Any
        ]
    }
    
    func refreshIfStale() {
        let now = Date()
        if now.timeIntervalSince(lastUpdate) > sampleInterval && !isRefreshing {
            DispatchQueue.global(qos: .background).async {
                self.refreshData()
            }
        }
    }
    
    private func refreshData() {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        
        DaemonLogger.shared.log("EnergyMonitor: Starting powermetrics sample...")
        
        let task = Process()
        task.launchPath = "/usr/bin/powermetrics"
        task.arguments = [
            "--samplers", "tasks",
            "--show-process-energy",
            "-n", "1",
            "-i", "500",
            "--format", "plist"
        ]
        
        let pipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = pipe
        task.standardError = errorPipe
        
        // Watchdog timer to prevent hangs
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
        timer.schedule(deadline: .now() + 15.0)
        timer.setEventHandler { [weak task] in
            if task?.isRunning == true {
                DaemonLogger.shared.log("EnergyMonitor: powermetrics timed out after 15s. Terminating.")
                task?.terminate()
            }
        }
        timer.resume()
        
        do {
            try task.run()
            
            // Optimization & Deadlock Fix: 
            // Reading concurrently with the process ensures the buffer never fills up.
            // readDataToEndOfFile() will block until the process finishes and closes the pipe.
            let dataRaw = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorRaw = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            task.waitUntilExit()
            timer.cancel()
            
            let exitCode = task.terminationStatus
            if exitCode != 0 && exitCode != 15 { // 15 is SIGTERM from our watchdog
                let errorString = String(data: errorRaw, encoding: .utf8) ?? "Unknown Error"
                self.lastError = "powermetrics failed (code \(exitCode)): \(errorString)"
                DaemonLogger.shared.log("EnergyMonitor: \(self.lastError!)")
                return
            }
            
            if exitCode == 15 {
                self.lastError = "powermetrics timed out and was terminated."
                return
            }
            
            var data = dataRaw
            
            // Robust parsing: extract only the <plist>...</plist> block
            if let outputString = String(data: data, encoding: .utf8) {
                if let startRange = outputString.range(of: "<plist"),
                   let endRange = outputString.range(of: "</plist>", options: .backwards) {
                    let cleanedString = String(outputString[startRange.lowerBound..<endRange.upperBound])
                    if let cleanedData = cleanedString.data(using: .utf8) {
                        data = cleanedData
                    }
                } else if outputString.isEmpty {
                     self.lastError = "powermetrics returned empty output."
                     DaemonLogger.shared.log("EnergyMonitor: Empty output.")
                     return
                }
            } else if let lastByte = data.last, lastByte == 0x00 {
                data.removeLast()
            }
            
            if let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
                parsePowermetricsPlist(plist)
                self.lastError = nil
            } else {
                self.lastError = "Failed to parse powermetrics output as plist (Data size: \(data.count))"
                DaemonLogger.shared.log("EnergyMonitor: \(self.lastError!)")
            }
        } catch {
            timer.cancel()
            self.lastError = "Process error: \(error.localizedDescription)"
            DaemonLogger.shared.log("EnergyMonitor: \(self.lastError!)")
        }
    }
    
    private func parsePowermetricsPlist(_ plist: [String: Any]) {
        guard let tasks = plist["tasks"] as? [[String: Any]] else {
            self.lastError = "Structure error: No 'tasks' array in plist."
            DaemonLogger.shared.log("EnergyMonitor: \(self.lastError!)")
            return
        }
        
        var results: [[String: Any]] = []
        for task in tasks {
            guard let name = task["name"] as? String,
                  let pid = task["pid"] as? Int,
                  let impact = task["energy_impact"] as? Double else { continue }
            
            var displayName = name
            if name.uppercased().contains("DEAD") {
                if let start = name.range(of: "("), let end = name.range(of: ")", options: .backwards) {
                    let extracted = String(name[name.index(after: start.lowerBound)..<end.lowerBound])
                    displayName = "Finished: \(extracted)"
                }
            }
            
            if impact < 0.01 { continue }
            
            results.append([
                "name": displayName,
                "pid": pid,
                "energy_impact": impact
            ])
        }
        
        results.sort { ($0["energy_impact"] as? Double ?? 0) > ($1["energy_impact"] as? Double ?? 0) }
        
        
        self.lastEnergyData = Array(results.prefix(25))
        self.lastUpdate = Date()
        
        // Log to database for historical analytics
        Database.shared.logEnergyUsage(consumers: self.lastEnergyData)
        
        DaemonLogger.shared.log("EnergyMonitor: Successfully updated with \(self.lastEnergyData.count) processes.")
    }
}
