import Foundation
import IOKit

extension String {
    var fourCharCode: UInt32 {
        var result: UInt32 = 0
        for char in self.utf8.prefix(4) {
            result = (result << 8) | UInt32(char)
        }
        return result
    }
}

class SMCVerifier {
    private var connection: io_connect_t = 0
    
    func open() -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return false }
        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        IOObjectRelease(service)
        return result == kIOReturnSuccess
    }
    
    func close() {
        if connection != 0 {
            IOServiceClose(connection)
            connection = 0
        }
    }
    
    func getInfo(_ key: String) -> (type: String, size: UInt32)? {
        var input = SMCParamStruct()
        var output = SMCParamStruct()
        input.key = key.fourCharCode
        input.data8 = UInt8(kSMCGetKeyInfo)
        var outputSize = MemoryLayout<SMCParamStruct>.stride
        let result = IOConnectCallStructMethod(connection, UInt32(kSMCHandleYPCEvent), &input, MemoryLayout<SMCParamStruct>.stride, &output, &outputSize)
        
        if result == kIOReturnSuccess && output.result == 0 {
            let t = typeStr(output.keyInfo.dataType)
            return (t, output.keyInfo.dataSize)
        }
        return nil
    }

    func readRaw(_ key: String, size: UInt32) -> [UInt8]? {
        var input = SMCParamStruct()
        var output = SMCParamStruct()
        input.key = key.fourCharCode
        input.keyInfo.dataSize = size
        input.data8 = UInt8(kSMCReadKey)
        var outputSize = MemoryLayout<SMCParamStruct>.stride
        let result = IOConnectCallStructMethod(connection, UInt32(kSMCHandleYPCEvent), &input, MemoryLayout<SMCParamStruct>.stride, &output, &outputSize)
        
        if result == kIOReturnSuccess && output.result == 0 {
            var bytes = [UInt8]()
            withUnsafePointer(to: &output.bytes) { pointer in
                let boundPtr = UnsafeRawPointer(pointer).bindMemory(to: UInt8.self, capacity: 32)
                for i in 0..<Int(size) {
                    bytes.append(boundPtr[i])
                }
            }
            return bytes
        }
        return nil
    }
    
    func typeStr(_ type: UInt32) -> String {
        let bytes = [
            UInt8((type >> 24) & 0xFF),
            UInt8((type >> 16) & 0xFF),
            UInt8((type >> 8) & 0xFF),
            UInt8(type & 0xFF)
        ]
        return String(bytes: bytes, encoding: .ascii) ?? "????"
    }

    func verifyOnce() {
        let keys = ["B0AC", "B0AV", "PSTR", "PDTR", "B0RM"]
        for key in keys {
            if let info = getInfo(key), let bytes = readRaw(key, size: info.size) {
                var val = ""
                if info.size == 2 {
                    let be = Int(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
                    let le = Int(UInt16(bytes[1]) << 8 | UInt16(bytes[0]))
                    let s_be = Int(Int16(bitPattern: UInt16(be)))
                    let s_le = Int(Int16(bitPattern: UInt16(le)))
                    val = "BE:\(be) LE:\(le) S_BE:\(s_be) S_LE:\(s_le)"
                } else if info.size == 4 {
                    if info.type == "flt " {
                        val = "Float: \(bytes.withUnsafeBytes { $0.load(as: Float.self) })"
                    } else {
                        val = "Raw: \(bytes)"
                    }
                }
                print("\(key) [\(info.type)]: \(val)")
            }
        }
    }
}

let verifier = SMCVerifier()
if verifier.open() {
    print("--- Polling live stats every 2 seconds (Ctrl+C to stop) ---")
    for _ in 1...5 {
        verifier.verifyOnce()
        print("----------")
        Thread.sleep(forTimeInterval: 2.0)
    }
    verifier.close()
} else {
    print("Failed to open SMC")
}
