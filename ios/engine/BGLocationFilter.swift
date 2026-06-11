import Foundation
import CoreLocation

@objc public class BGLocationFilterResult: NSObject {

    @objc public var decision: Bool = true
    @objc public var reason: String = ""
    @objc public var accuracy: CLLocationAccuracy = 0
    @objc public var speed: CLLocationSpeed = 0
    @objc public var deltaRaw: Double = 0
    @objc public var deltaSmoothed: Double = 0
    @objc public var deltaEffective: Double = 0
    @objc public var distanceFilter: CLLocationDistance = 0
    @objc public var odometerSigma: Double = 0
    @objc public var cap: Double = 0

    @objc public override var description: String {
        return "<BGLocationFilterResult decision=\(decision) reason=\(reason) delta=\(deltaEffective)>"
    }
}

@objc public class BGLocationFilter: NSObject {

    @objc public var type: String = "NONE"
    @objc public var policy: String = "NONE"
    @objc public var configured: Bool = false
    @objc public var debug: Bool = false
    @objc public var useKalman: Bool = false
    @objc public var kalmanDebug: Bool = false
    @objc public var kalmanProfile: String = "default"
    @objc public var accuracyThreshold: CLLocationAccuracy = 0

    private var accumulatedAccuracySquaredValue: Double = 0
    private var kalman: BGKalmanFilter?

    @objc public init(type: String) {
        self.type = type
        super.init()
    }

    @objc public override init() {
        super.init()
    }

    @objc public func configure(_ config: BGLocationFilterConfig) {
        applyConfig(config)
    }

    @objc public func applyConfig(_ config: BGLocationFilterConfig) {
        policy = config.policy
        debug = config.filterDebug
        useKalman = config.useKalman
        kalmanDebug = config.kalmanDebug
        kalmanProfile = config.kalmanProfile
        accuracyThreshold = config.odometerAccuracyThreshold
        configured = true
    }

    @objc public func evaluateWithMetrics(_ metrics: BGLocationMetrics) -> BGLocationFilterResult {
        let result = BGLocationFilterResult()
        result.decision = true
        result.reason = "PASS"
        return result
    }

    @objc public func reset() {
        accumulatedAccuracySquaredValue = 0
        kalman = nil
    }

    @objc public func onMotionChange(_ isMoving: Bool) {
        reset()
    }

    @objc public func accumulateAccuracy(withMeasurement measurement: Double) {
        accumulatedAccuracySquaredValue += measurement * measurement
    }

    @objc public func seedAccumulatedAccuracySquared(_ value: Double) {
        accumulatedAccuracySquaredValue = value
    }
}
