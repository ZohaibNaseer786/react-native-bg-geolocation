import Foundation

public func TSLogLevelToString(_ level: Int) -> String {
    switch level {
    case 0: return "off"
    case 1: return "error"
    case 2: return "warning"
    case 3: return "info"
    case 4: return "debug"
    case 5: return "verbose"
    default: return "unknown"
    }
}

public func TSLogLevelFromString(_ string: String?, _ defaultLevel: Int) -> Int {
    guard let string = string, !string.isEmpty else { return defaultLevel }
    switch string.lowercased() {
    case "off": return 0
    case "error": return 1
    case "warning": return 2
    case "info": return 3
    case "debug": return 4
    case "verbose": return 5
    default: return defaultLevel
    }
}
