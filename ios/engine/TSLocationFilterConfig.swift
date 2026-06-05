import Foundation

@objc public class TSLocationFilterConfig: TSConfigModuleBase {

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

    @objc public override func propertySpecs() -> [TSPropertySpecImpl] {
        return [
            TSPropertySpec(name: "policy", type: "string"),
            TSPropertySpec(name: "burstWindow", type: "double"),
            TSPropertySpec(name: "maxBurstDistance", type: "double"),
            TSPropertySpec(name: "rollingWindow", type: "int"),
            TSPropertySpec(name: "maxImpliedSpeed", type: "double"),
            TSPropertySpec(name: "odometerAccuracyThreshold", type: "double"),
            TSPropertySpec(name: "odometerUseKalmanFilter", type: "bool"),
            TSPropertySpec(name: "trackingAccuracyThreshold", type: "double"),
            TSPropertySpec(name: "filterDebug", type: "bool"),
            TSPropertySpec(name: "useKalman", type: "bool"),
            TSPropertySpec(name: "kalmanDebug", type: "bool"),
            TSPropertySpec(name: "kalmanProfile", type: "string")
        ]
    }
}
