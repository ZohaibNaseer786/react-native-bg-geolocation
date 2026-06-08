import Foundation

@objc public class TSAppConfig: TSConfigModuleBase {

    @objc public var stopOnTerminate: Bool = true
    @objc public var startOnBoot: Bool = false
    @objc public var preventSuspend: Bool = false
    @objc public var heartbeatInterval: Double = 60.0
    @objc public var schedule: [String] = []
    @objc public var liveActivityEnabled: Bool = false
    @objc public var liveActivityTitle: String = "Live location"
    @objc public var liveActivitySubtitle: String = "Background tracking is active"
    @objc public var liveActivityUpdateInterval: Double = 15.0
    @objc public var liveActivityStaleSeconds: Double = 120.0
    @objc public var liveActivityPushUpdates: Bool = false
    @objc public var locationPushEnabled: Bool = false
    @objc public var trackingAudioEnabled: Bool = false
    @objc public var trackingAudioVolume: Double = 0.04
    @objc public var trackingAudioMixWithOthers: Bool = true

    @objc public override func applyDefaults() {
        stopOnTerminate = true
        startOnBoot = false
        preventSuspend = false
        heartbeatInterval = 60.0
        schedule = []
        liveActivityEnabled = false
        liveActivityTitle = "Live location"
        liveActivitySubtitle = "Background tracking is active"
        liveActivityUpdateInterval = 15.0
        liveActivityStaleSeconds = 120.0
        liveActivityPushUpdates = false
        locationPushEnabled = false
        trackingAudioEnabled = false
        trackingAudioVolume = 0.04
        trackingAudioMixWithOthers = true
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
            TSPropertySpec(name: "schedule", type: "array"),
            TSPropertySpec(name: "liveActivityEnabled", type: "bool"),
            TSPropertySpec(name: "liveActivityTitle", type: "string"),
            TSPropertySpec(name: "liveActivitySubtitle", type: "string"),
            TSPropertySpec(name: "liveActivityUpdateInterval", type: "double"),
            TSPropertySpec(name: "liveActivityStaleSeconds", type: "double"),
            TSPropertySpec(name: "liveActivityPushUpdates", type: "bool"),
            TSPropertySpec(name: "locationPushEnabled", type: "bool"),
            TSPropertySpec(name: "trackingAudioEnabled", type: "bool"),
            TSPropertySpec(name: "trackingAudioVolume", type: "double"),
            TSPropertySpec(name: "trackingAudioMixWithOthers", type: "bool")
        ]
    }

    @objc public override func contributeDeprecatedProperties(_ dict: NSMutableDictionary, redact: Bool) {
        dict["stopOnTerminate"] = stopOnTerminate
        dict["startOnBoot"] = startOnBoot
        dict["preventSuspend"] = preventSuspend
        dict["heartbeatInterval"] = heartbeatInterval
        dict["schedule"] = schedule
        dict["liveActivityEnabled"] = liveActivityEnabled
        dict["liveActivityTitle"] = liveActivityTitle
        dict["liveActivitySubtitle"] = liveActivitySubtitle
        dict["liveActivityUpdateInterval"] = liveActivityUpdateInterval
        dict["liveActivityStaleSeconds"] = liveActivityStaleSeconds
        dict["liveActivityPushUpdates"] = liveActivityPushUpdates
        dict["locationPushEnabled"] = locationPushEnabled
        dict["trackingAudioEnabled"] = trackingAudioEnabled
        dict["trackingAudioVolume"] = trackingAudioVolume
        dict["trackingAudioMixWithOthers"] = trackingAudioMixWithOthers
    }

    @objc public override func validateConfiguration() -> Bool {
        return true
    }

    @objc public override var description: String {
        return "<TSAppConfig stopOnTerminate=\(stopOnTerminate) startOnBoot=\(startOnBoot) preventSuspend=\(preventSuspend) heartbeatInterval=\(heartbeatInterval)>"
    }
}
