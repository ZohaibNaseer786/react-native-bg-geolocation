import Foundation
import CoreLocation

@objc public class BGLocationMetrics: NSObject {

    @objc public var accuracyCurrent: CLLocationAccuracy = 0
    @objc public var accuracyPrev: CLLocationAccuracy = 0
    @objc public var speed: CLLocationSpeed = 0
    @objc public var speedStability: Double = 0
    @objc public var bearing: CLLocationDirection = 0
    @objc public var bearingStability: Double = 0
    @objc public var course: CLLocationDirection = 0
    @objc public var deltaHeading: Double = 0
    @objc public var headingChangeRate: Double = 0
    @objc public var headingQuality: Double = 0
    @objc public var dt: Double = 0
    @objc public var distanceFilter: CLLocationDistance = 10
    @objc public var jerk: Double = 0
    @objc public var isStationary: Bool = false
    @objc public var isOscillating: Bool = false
    @objc public var stationaryConfidence: Double = 0
    @objc public var impliedSpeed: Double = 0
    @objc public var impliedAnomaly: Bool = false
    @objc public var rollingAverage: Double = 0
    @objc public var raw: Double = 0
    @objc public var effective: Double = 0
    @objc public var accCap: Double = 0
    @objc public var burstCap: Double = 0
    @objc public var kinCap: Double = 0
    @objc public var capCandidate: Double = 0
}

@objc public class BGLocationMetricsEngine: NSObject {

    @objc public var config: BGLocationFilterConfig?
    @objc public var filterDebug: Bool = false
    @objc public var burstWindow: Double = 60.0
    @objc public var maxBurstDistance: Double = 100.0
    @objc public var maxImpliedSpeed: Double = 514.0
    @objc public var rollingWindow: Int = 10
    @objc public var last: CLLocation?
    @objc public var lastBearingDeg: Double = 0
    @objc public var lastBearingValid: Bool = false

    private var rbBuffer: [Double] = []
    @objc public var rbCount: Int = 0
    @objc public var rbHead: Int = 0
    @objc public var rbSum: Double = 0

    @objc public init(withConfig config: BGLocationFilterConfig) {
        self.config = config
        super.init()
        applyConfig(config)
    }

    @objc public override init() {
        super.init()
    }

    @objc public func applyConfig(_ config: BGLocationFilterConfig) {
        self.config = config
        filterDebug = config.filterDebug
        burstWindow = config.burstWindow
        maxBurstDistance = config.maxBurstDistance
        maxImpliedSpeed = config.maxImpliedSpeed
        rollingWindow = config.rollingWindow
        rbBuffer = Array(repeating: 0.0, count: rollingWindow)
    }

    @objc public func computeFor(
        _ current: CLLocation,
        previous: CLLocation?,
        distanceFilter: CLLocationDistance
    ) -> BGLocationMetrics {
        let metrics = BGLocationMetrics()
        metrics.accuracyCurrent = current.horizontalAccuracy
        metrics.speed = current.speed
        metrics.bearing = current.course
        metrics.distanceFilter = distanceFilter

        if let prev = previous {
            metrics.dt = current.timestamp.timeIntervalSince(prev.timestamp)
            metrics.raw = current.distance(from: prev)
            if metrics.dt > 0 {
                metrics.impliedSpeed = metrics.raw / metrics.dt
                metrics.impliedAnomaly = metrics.impliedSpeed > maxImpliedSpeed
            }
            metrics.deltaHeading = abs(current.course - prev.course)
        }

        return metrics
    }

    @objc public func computeStationaryMetrics(_ metrics: BGLocationMetrics, current: CLLocation) {
        metrics.isStationary = metrics.speed < 0.5
        metrics.stationaryConfidence = metrics.isStationary ? 1.0 : 0.0
    }

    @objc public func reset() {
        last = nil
        lastBearingValid = false
        lastBearingDeg = 0
        rbBuffer = Array(repeating: 0.0, count: rollingWindow)
        rbCount = 0
        rbHead = 0
        rbSum = 0
    }

    @objc public func onMotionChange(_ isMoving: Bool) {
        reset()
    }

    @objc public override var description: String {
        return "<BGLocationMetricsEngine rollingWindow=\(rollingWindow)>"
    }
}
