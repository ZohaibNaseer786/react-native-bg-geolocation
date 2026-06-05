import Foundation

@objc public class TSAppConfig: TSConfigModuleBase {

    @objc public var stopOnTerminate: Bool = true
    @objc public var startOnBoot: Bool = false
    @objc public var preventSuspend: Bool = false
    @objc public var heartbeatInterval: Double = 60.0
    @objc public var schedule: [String] = []

    @objc public override func applyDefaults() {
        stopOnTerminate = true
        startOnBoot = false
        preventSuspend = false
        heartbeatInterval = 60.0
        schedule = []
    }

    @objc public var hasSchedule: Bool {
        return !schedule.isEmpty
    }

    @objc public var isBackgroundExecutionEnabled: Bool {
        return !stopOnTerminate || startOnBoot || preventSuspend
    }

    @objc public override func propertySpecs() -> [TSPropertySpecImpl] {
        return [
            TSPropertySpec(name: "stopOnTerminate", type: "bool"),
            TSPropertySpec(name: "startOnBoot", type: "bool"),
            TSPropertySpec(name: "preventSuspend", type: "bool"),
            TSPropertySpec(name: "heartbeatInterval", type: "double"),
            TSPropertySpec(name: "schedule", type: "array")
        ]
    }

    @objc public override func contributeDeprecatedProperties(_ dict: NSMutableDictionary, redact: Bool) {
        dict["stopOnTerminate"] = stopOnTerminate
        dict["startOnBoot"] = startOnBoot
        dict["preventSuspend"] = preventSuspend
        dict["heartbeatInterval"] = heartbeatInterval
        dict["schedule"] = schedule
    }

    @objc public override func validateConfiguration() -> Bool {
        return true
    }

    @objc public override var description: String {
        return "<TSAppConfig stopOnTerminate=\(stopOnTerminate) startOnBoot=\(startOnBoot) preventSuspend=\(preventSuspend) heartbeatInterval=\(heartbeatInterval)>"
    }
}
