import Foundation
import os
import SQLite3

let dbLogger = Logger(subsystem: "com.chargecontrol.daemon", category: "Database")

class Database {
    static let shared = Database()
    private var db: OpaquePointer?
    
    private init() {
        let fileManager = FileManager.default
        let dbPath = "/Library/Application Support/ChargeControl/history.db"
        
        // Ensure directory exists
        let folder = "/Library/Application Support/ChargeControl"
        if !fileManager.fileExists(atPath: folder) {
            try? fileManager.createDirectory(atPath: folder, withIntermediateDirectories: true)
        }
        
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            dbLogger.error("Unable to open database.")
            return
        }
        
        createTable()
        pruneOldHistory()
    }
    
    private func pruneOldHistory() {
        // 1. Aggregate yesterday's data into DailyStats if not already present
        let aggregateQuery = """
        INSERT OR IGNORE INTO DailyStats (date, avg_health, cycle_count, max_temp, avg_system_power)
        SELECT 
            date(timestamp),
            avg(percentage), -- Simplified health proxy for now
            max(id), -- Temporary proxy for cycle count if not logged separately
            max(temperature),
            avg(system_power)
        FROM BatteryHistory
        WHERE date(timestamp) < date('now')
        GROUP BY date(timestamp);
        """
        sqlite3_exec(db, aggregateQuery, nil, nil, nil)

        // 2. Delete records older than 30 days
        let pruneStatementString = "DELETE FROM BatteryHistory WHERE timestamp < datetime('now', '-30 days');"
        var pruneStatement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, pruneStatementString, -1, &pruneStatement, nil) == SQLITE_OK {
            if sqlite3_step(pruneStatement) == SQLITE_DONE {
                dbLogger.info("Old database history pruned and aggregated successfully.")
            } else {
                dbLogger.error("Failed to prune old history.")
            }
        }
        sqlite3_finalize(pruneStatement)
        
        // Optional: Vacuum to reclaim space
        sqlite3_exec(db, "VACUUM;", nil, nil, nil)
    }
    
    private func createTable() {
        let createHistoryTable = """
        CREATE TABLE IF NOT EXISTS BatteryHistory(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
            percentage INTEGER,
            voltage REAL,
            amperage INTEGER,
            system_power REAL,
            battery_power REAL,
            temperature REAL
        );
        """
        
        let createStatsTable = """
        CREATE TABLE IF NOT EXISTS DailyStats(
            date DATE PRIMARY KEY,
            avg_health REAL,
            cycle_count INTEGER,
            max_temp REAL,
            avg_system_power REAL
        );
        """
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, createHistoryTable, -1, &statement, nil) == SQLITE_OK {
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
        
        if sqlite3_prepare_v2(db, createStatsTable, -1, &statement, nil) == SQLITE_OK {
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
    }
    
    func logStats(percentage: Int, voltage: Double, amperage: Int, systemPower: Double, batteryPower: Double, temp: Double) {
        let insertStatementString = "INSERT INTO BatteryHistory (percentage, voltage, amperage, system_power, battery_power, temperature) VALUES (?, ?, ?, ?, ?, ?);"
        var insertStatement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, insertStatementString, -1, &insertStatement, nil) == SQLITE_OK {
            sqlite3_bind_int(insertStatement, 1, Int32(percentage))
            sqlite3_bind_double(insertStatement, 2, voltage)
            sqlite3_bind_int(insertStatement, 3, Int32(amperage))
            sqlite3_bind_double(insertStatement, 4, systemPower)
            sqlite3_bind_double(insertStatement, 5, batteryPower)
            sqlite3_bind_double(insertStatement, 6, temp)
            
            if sqlite3_step(insertStatement) == SQLITE_DONE {
                // Success
            } else {
                dbLogger.error("Could not insert row.")
            }
        }
        sqlite3_finalize(insertStatement)
    }
    
    func getHistory(limit: Int = 100) -> [[String: Any]] {
        let queryStatementString = "SELECT timestamp, percentage, voltage, amperage, system_power, battery_power, temperature FROM BatteryHistory ORDER BY id DESC LIMIT ?;"
        var queryStatement: OpaquePointer?
        var results = [[String: Any]]()
        
        if sqlite3_prepare_v2(db, queryStatementString, -1, &queryStatement, nil) == SQLITE_OK {
            sqlite3_bind_int(queryStatement, 1, Int32(limit))
            
            while sqlite3_step(queryStatement) == SQLITE_ROW {
                let timestamp = String(cString: sqlite3_column_text(queryStatement, 0))
                let percentage = sqlite3_column_int(queryStatement, 1)
                let voltage = sqlite3_column_double(queryStatement, 2)
                let amperage = sqlite3_column_int(queryStatement, 3)
                let system_power = sqlite3_column_double(queryStatement, 4)
                let battery_power = sqlite3_column_double(queryStatement, 5)
                let temperature = sqlite3_column_double(queryStatement, 6)
                
                results.append([
                    "timestamp": timestamp,
                    "percentage": Int(percentage),
                    "voltage": voltage,
                    "amperage": Int(amperage),
                    "system_power": system_power,
                    "battery_power": battery_power,
                    "temperature": temperature
                ])
            }
        }
        sqlite3_finalize(queryStatement)
        return results
    }
}
