import Foundation
import IOKit
import os

let smcLogger = Logger(subsystem: "com.chargecontrol.daemon", category: "SMC")

public struct SMCComm {
    private static var connection: io_connect_t = 0
    
    public static func open() -> Bool {
        guard connection == 0 else { return true }
        
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else {
            smcLogger.error("Failed to find AppleSMC service")
            return false
        }
        defer { IOObjectRelease(service) }
        
        var conn: io_connect_t = 0
        // Use type 1 (kSMCUserClientType)
        let result = IOServiceOpen(service, mach_task_self_, 1, &conn)
        guard result == kIOReturnSuccess else {
            smcLogger.error("Failed to open AppleSMC service: \(result)")
            return false
        }
        
        connection = conn
        
        let openResult = IOConnectCallMethod(connection, UInt32(kSMCUserClientOpen), nil, 0, nil, 0, nil, nil, nil, nil)
        if openResult != kIOReturnSuccess {
            smcLogger.error("Failed to call openClient: \(openResult)")
        }
        
        return true
    }
    
    public static func close() {
        guard connection != 0 else { return }
        IOConnectCallMethod(connection, UInt32(kSMCUserClientClose), nil, 0, nil, 0, nil, nil, nil, nil)
        IOServiceClose(connection)
        connection = 0
    }
    
    private static func callSMCFunctionYPC(input: inout SMCParamStruct, output: inout SMCParamStruct) -> kern_return_t {
        var outputSize = MemoryLayout<SMCParamStruct>.stride
        let result = IOConnectCallStructMethod(connection, UInt32(kSMCHandleYPCEvent), &input, MemoryLayout<SMCParamStruct>.stride, &output, &outputSize)
        if result != kIOReturnSuccess {
            smcLogger.error("IOConnectCallStructMethod failed: \(result)")
        } else {
            let smcResult = output.result
            if smcResult != UInt8(kSMCSuccess) {
                if smcResult == 132 {
                    // 132 is kSMCKeyNotFound, expected for unsupported sensors
                    smcLogger.debug("SMC function returned key not found (132)")
                } else {
                    smcLogger.error("SMC function returned error result: \(smcResult)")
                }
            }
        }
        return result
    }
    
    public static func writeKey(_ key: String, value: [UInt8]) -> Bool {
        guard open() else { return false }
        
        smcLogger.info("SMC: Writing key \(key) with value \(value)")
        
        var input = SMCParamStruct()
        var output = SMCParamStruct()
        
        input.key = key.fourCharCode
        input.keyInfo.dataSize = UInt32(value.count)
        input.data8 = UInt8(kSMCWriteKey)
        
        withUnsafeMutablePointer(to: &input.bytes) { pointer in
            let boundPtr = UnsafeMutableRawPointer(pointer).bindMemory(to: UInt8.self, capacity: 32)
            for (i, byte) in value.enumerated() {
                boundPtr[i] = byte
            }
        }
        
        let result = callSMCFunctionYPC(input: &input, output: &output)
        let success = result == kIOReturnSuccess && output.result == UInt8(kSMCSuccess)
        smcLogger.info("SMC: Write key \(key) success: \(success)")
        
        // Verification read
        if success {
            if let readVal = readKey(key), readVal == value {
                return true
            }
            smcLogger.warning("SMC: Write reported success but verification read failed or mismatched for \(key)")
        }
        
        return success
    }

    public static func readKey(_ key: String) -> [UInt8]? {
        guard open() else { return nil }
        
        var input = SMCParamStruct()
        var output = SMCParamStruct()
        
        // Get Key Info first
        input.key = key.fourCharCode
        input.data8 = UInt8(kSMCGetKeyInfo)
        
        var result = callSMCFunctionYPC(input: &input, output: &output)
        guard result == kIOReturnSuccess && output.result == UInt8(kSMCSuccess) else {
            if output.result == 132 {
                smcLogger.debug("SMC: Key not found \(key)")
            } else {
                smcLogger.error("SMC: Failed to get info for key \(key)")
            }
            return nil
        }
        
        let size = output.keyInfo.dataSize
        
        // Read the Key
        input.keyInfo.dataSize = size
        input.data8 = UInt8(kSMCReadKey)
        
        result = callSMCFunctionYPC(input: &input, output: &output)
        guard result == kIOReturnSuccess && output.result == UInt8(kSMCSuccess) else {
            smcLogger.error("SMC: Failed to read key \(key)")
            return nil
        }
        
        var bytes = [UInt8]()
        withUnsafePointer(to: &output.bytes) { pointer in
            let boundPtr = UnsafeRawPointer(pointer).bindMemory(to: UInt8.self, capacity: 32)
            for i in 0..<Int(size) {
                bytes.append(boundPtr[i])
            }
        }
        smcLogger.info("SMC: Read key \(key) value: \(bytes)")
        return bytes
    }

    public static func readTemperature(_ key: String) -> Double? {
        guard let bytes = readKey(key) else { return nil }
        
        if bytes.count == 2 {
            // Most thermal sensors on Apple Silicon use sp78 (Big-Endian)
            let raw = (Int16(bytes[0]) << 8) | Int16(bytes[1])
            return Double(raw) / 256.0
        } else if bytes.count == 4 {
            // millicentigrade (usually Little-Endian on ARM)
            let raw = bytes.withUnsafeBytes { $0.load(as: Int32.self) }
            return Double(raw) / 100.0
        }
        return nil
    }

    public static func readInt16LE(_ key: String) -> Int16? {
        guard let bytes = readKey(key), bytes.count == 2 else { return nil }
        let raw = (UInt16(bytes[1]) << 8) | UInt16(bytes[0])
        return Int16(bitPattern: raw)
    }

    public static func readUInt16LE(_ key: String) -> UInt16? {
        guard let bytes = readKey(key), bytes.count == 2 else { return nil }
        return (UInt16(bytes[1]) << 8) | UInt16(bytes[0])
    }

    public static func readInt16BE(_ key: String) -> Int16? {
        guard let bytes = readKey(key), bytes.count == 2 else { return nil }
        let raw = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
        return Int16(bitPattern: raw)
    }

    public static func readUInt16BE(_ key: String) -> UInt16? {
        guard let bytes = readKey(key), bytes.count == 2 else { return nil }
        return (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
    }

    public static func readFloat(_ key: String) -> Float? {
        guard let bytes = readKey(key), bytes.count == 4 else { return nil }
        return bytes.withUnsafeBytes { $0.load(as: Float.self) }
    }

    public static func readInt32(_ key: String) -> Int32? {
        guard let bytes = readKey(key), bytes.count == 4 else { return nil }
        return bytes.withUnsafeBytes { $0.load(as: Int32.self) }
    }

    public static func readUInt32(_ key: String) -> UInt32? {
        guard let bytes = readKey(key), bytes.count == 4 else { return nil }
        return bytes.withUnsafeBytes { $0.load(as: UInt32.self) }
    }

    public enum MagSafeColor: UInt8 {
        case system = 0x00
        case off    = 0x01
        case green  = 0x03
        case orange = 0x04
        case orangeSlowBlink = 0x06
        case orangeFastBlink = 0x07
    }

    public static func setMagSafeColor(_ color: MagSafeColor) -> Bool {
        return writeKey("ACLC", value: [color.rawValue])
    }

    public static func cycleAdapter() {
        smcLogger.info("SMC: Cycling power adapter to force state recognition.")
        // Briefly disable the adapter
        _ = writeKey("CHIE", value: [0x08])
        _ = writeKey("CH0J", value: [0x20])
        
        // Wait 250ms and re-enable
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) {
            _ = writeKey("CHIE", value: [0x00])
            _ = writeKey("CH0J", value: [0x00])
        }
    }
}

extension String {
    var fourCharCode: UInt32 {
        var result: UInt32 = 0
        for char in self.utf8.prefix(4) {
            result = (result << 8) | UInt32(char)
        }
        return result
    }
}
