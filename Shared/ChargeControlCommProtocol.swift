import Foundation

@objc public protocol ChargeControlDaemonProtocol {
    func getUniqueId(reply: @escaping (String?) -> Void)
    func getState(reply: @escaping ([String: Any]?) -> Void)
    func getSettings(reply: @escaping ([String: Any]?) -> Void)
    func setSettings(settings: [String: Any], reply: @escaping (Int32) -> Void)
    func execute(command: Int32, reply: @escaping (Int32) -> Void)
    func getHistory(reply: @escaping ([[String: Any]]?) -> Void)
}

public enum ChargeControlCommand: Int32 {
    case disablePowerAdapter = 0
    case enablePowerAdapter  = 1
    case chargeToFull        = 2
    case chargeToLimit       = 3
    case disableCharging     = 4
    case isSupported         = 5
    case testMagSafe         = 6
}
