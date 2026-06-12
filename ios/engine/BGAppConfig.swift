import Foundation

@objc public class BGAppConfig: BGConfigModuleBase {

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

    @objc public override func propertySpecs() -> [BGPropertySpecImpl] {
        return [
            BGPropertySpec(name: "stopOnTerminate", type: "bool"),
            BGPropertySpec(name: "startOnBoot", type: "bool"),
            BGPropertySpec(name: "preventSuspend", type: "bool"),
            BGPropertySpec(name: "heartbeatInterval", type: "double"),
            BGPropertySpec(name: "schedule", type: "array"),
            BGPropertySpec(name: "liveActivityEnabled", type: "bool"),
            BGPropertySpec(name: "liveActivityTitle", type: "string"),
            BGPropertySpec(name: "liveActivitySubtitle", type: "string"),
            BGPropertySpec(name: "liveActivityUpdateInterval", type: "double"),
            BGPropertySpec(name: "liveActivityStaleSeconds", type: "double"),
            BGPropertySpec(name: "liveActivityPushUpdates", type: "bool"),
            BGPropertySpec(name: "locationPushEnabled", type: "bool"),
            BGPropertySpec(name: "trackingAudioEnabled", type: "bool"),
            BGPropertySpec(name: "trackingAudioVolume", type: "double"),
            BGPropertySpec(name: "trackingAudioMixWithOthers", type: "bool")
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
        return "<BGAppConfig stopOnTerminate=\(stopOnTerminate) startOnBoot=\(startOnBoot) preventSuspend=\(preventSuspend) heartbeatInterval=\(heartbeatInterval)>"
    }
}
