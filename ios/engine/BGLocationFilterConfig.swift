import Foundation

@objc public class BGLocationFilterConfig: BGConfigModuleBase {

    @objc public var policy: String = "NONE"
    @objc public var burstWindow: Double = 60.0
    @objc public var maxBurstDistance: Double = 100.0
    @objc public var rollingWindow: Int = 10
    @objc public var maxImpliedSpeed: Double = 514.0
    @objc public var odometerAccuracyThreshold: Double = 100.0
    @objc public var odometerUseKalmanFilter: Bool = true
    @objc public var trackingAccuracyThreshold: Double = 0.0
    @objc public var filterDebug: Bool = false
    @objc public var useKalman: Bool = false
    @objc public var kalmanDebug: Bool = false
    @objc public var kalmanProfile: String = "default"

    @objc public override func applyDefaults() {
        policy = "NONE"
        burstWindow = 60.0
        maxBurstDistance = 100.0
        rollingWindow = 10
        maxImpliedSpeed = 514.0
        odometerAccuracyThreshold = 100.0
        odometerUseKalmanFilter = true
        trackingAccuracyThreshold = 0.0
        filterDebug = false
        useKalman = false
        kalmanDebug = false
        kalmanProfile = "default"
    }

    @objc public func moduleKey() -> String {
        return "filter"
    }

    @objc public override func deprecatedPropertyMappings() -> [String: String] {
        return [:]
    }

    @objc public override func propertySpecs() -> [BGPropertySpecImpl] {
        return [
            BGPropertySpec(name: "policy", type: "string"),
            BGPropertySpec(name: "burstWindow", type: "double"),
            BGPropertySpec(name: "maxBurstDistance", type: "double"),
            BGPropertySpec(name: "rollingWindow", type: "int"),
            BGPropertySpec(name: "maxImpliedSpeed", type: "double"),
            BGPropertySpec(name: "odometerAccuracyThreshold", type: "double"),
            BGPropertySpec(name: "odometerUseKalmanFilter", type: "bool"),
            BGPropertySpec(name: "trackingAccuracyThreshold", type: "double"),
            BGPropertySpec(name: "filterDebug", type: "bool"),
            BGPropertySpec(name: "useKalman", type: "bool"),
            BGPropertySpec(name: "kalmanDebug", type: "bool"),
            BGPropertySpec(name: "kalmanProfile", type: "string")
        ]
    }
}
