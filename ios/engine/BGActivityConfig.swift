import Foundation

@objc public final class BGActivityConfig: BGConfigModuleBase {

    @objc public var disableMotionActivityUpdates: Bool = false
    @objc public var disableStopDetection: Bool = false
    @objc public var stopOnStationary: Bool = false
    @objc public var stopDetectionDelay: Double = 0
    @objc public var activityRecognitionInterval: Double = 0
    @objc public var minimumActivityRecognitionConfidence: Int = 0
    @objc public var triggerActivities: String = ""

    @objc public override func applyDefaults() {
        stopDetectionDelay = 0
        activityRecognitionInterval = 10000.0
        minimumActivityRecognitionConfidence = 70
        disableMotionActivityUpdates = false
        disableStopDetection = false
        stopOnStationary = false
        triggerActivities = ""
    }

    @objc public override func propertySpecs() -> [BGPropertySpecImpl] {
        return [
            BGPropertySpecImpl(name: "stopDetectionDelay", type: "integer"),
            BGPropertySpecImpl(name: "activityRecognitionInterval", type: "integer"),
            BGPropertySpecImpl(name: "minimumActivityRecognitionConfidence", type: "integer"),
            BGPropertySpecImpl(name: "disableMotionActivityUpdates", type: "bool"),
            BGPropertySpecImpl(name: "disableStopDetection", type: "bool"),
            BGPropertySpecImpl(name: "stopOnStationary", type: "bool"),
            BGPropertySpecImpl(name: "triggerActivities", type: "string")
        ]
    }

    @objc public override func contributeDeprecatedProperties(_ dict: NSMutableDictionary, redact: Bool) {
        dict.setObject(NSNumber(value: stopDetectionDelay), forKey: "stopDetectionDelay" as NSString)
        dict.setObject(NSNumber(value: activityRecognitionInterval), forKey: "activityRecognitionInterval" as NSString)
        dict.setObject(NSNumber(value: minimumActivityRecognitionConfidence), forKey: "minimumActivityRecognitionConfidence" as NSString)
        dict.setObject(NSNumber(value: disableMotionActivityUpdates), forKey: "disableMotionActivityUpdates" as NSString)
        dict.setObject(NSNumber(value: disableStopDetection), forKey: "disableStopDetection" as NSString)
        dict.setObject(NSNumber(value: stopOnStationary), forKey: "stopOnStationary" as NSString)
        dict.setObject(triggerActivities, forKey: "triggerActivities" as NSString)
    }

    @objc public override func validateConfiguration() -> Bool {
        if disableStopDetection && stopOnStationary {
            let logger = BGLog.sharedInstance()
            if logger.shouldLog(2) {
                let message = "BGActivityConfig: stopOnStationary is enabled but disableStopDetection is also enabled - stopOnStationary will have no effect"
                logger.log(2, tag: 9, function: "-[BGActivityConfig validateConfiguration]", message: message)
            }
        }
        if disableMotionActivityUpdates && !disableStopDetection {
            let logger = BGLog.sharedInstance()
            if logger.shouldLog(2) {
                let message = "BGActivityConfig: Motion activity updates are disabled but stop detection is enabled - stop detection may not work properly"
                logger.log(2, tag: 9, function: "-[BGActivityConfig validateConfiguration]", message: message)
            }
        }
        return true
    }

    public override var description: String {
        return String(format: "<%@: %p> {\n  stopDetectionDelay: %.0fs\n  activityRecognitionInterval: %.0f ms\n  minimumActivityRecognitionConfidence: %ld%%\n  disableMotionActivityUpdates: %@\n  disableStopDetection: %@\n  stopOnStationary: %@\n}",
                      String(describing: type(of: self)), self,
                      stopDetectionDelay, activityRecognitionInterval, minimumActivityRecognitionConfidence,
                      disableMotionActivityUpdates ? "YES" : "NO",
                      disableStopDetection ? "YES" : "NO",
                      stopOnStationary ? "YES" : "NO")
    }
}
