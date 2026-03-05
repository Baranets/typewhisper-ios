import Foundation

enum AccessoryBatteryStatus: Equatable, Sendable {
    case unavailable
    case level(Int)
}

protocol AccessoryBatteryMonitoring: Sendable {
    func currentStatus() -> AccessoryBatteryStatus
}

struct UnavailableAccessoryBatteryMonitor: AccessoryBatteryMonitoring {
    func currentStatus() -> AccessoryBatteryStatus {
        .unavailable
    }
}
