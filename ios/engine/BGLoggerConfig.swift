import Foundation

@objc public class BGLoggerConfig: BGConfigModuleBase {

    @objc public var logLevel: Int = 5
    @objc public var logMaxDays: Int = 3
    @objc public var debug: Bool = false

    @objc public class func logLevel(fromString s: String) -> Int {
        switch s.uppercased() {
        case "OFF": return 0
        case "ERROR": return 1
        case "WARN", "WARNING": return 2
        case "INFO": return 3
        case "DEBUG": return 4
        case "VERBOSE", "TRACE": return 5
        default: return 3
        }
    }

    @objc public class func string(forLogLevel level: Int) -> String {
        switch level {
        case 0: return "OFF"
        case 1: return "ERROR"
        case 2: return "WARN"
        case 3: return "INFO"
        case 4: return "DEBUG"
        case 5: return "VERBOSE"
        default: return "INFO"
        }
    }

    @objc public override func applyDefaults() {
        logLevel = 5
        logMaxDays = 3
        debug = false
    }

    @objc public override func contributeDeprecatedProperties(_ dict: NSMutableDictionary, redact: Bool) {
        dict["logLevel"] = logLevel
        dict["logMaxDays"] = logMaxDays
        dict["debug"] = debug
    }

    @objc public override func propertySpecs() -> [BGPropertySpecImpl] {
        return [
            BGPropertySpec(name: "logLevel", type: "int"),
            BGPropertySpec(name: "logMaxDays", type: "int"),
            BGPropertySpec(name: "debug", type: "bool")
        ]
    }

    @objc public override func validateConfiguration() -> Bool {
        return true
    }

    @objc public override var description: String {
        return "<BGLoggerConfig logLevel=\(logLevel) logMaxDays=\(logMaxDays) debug=\(debug)>"
    }
}
