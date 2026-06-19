import Foundation
import CoreLocation

@objc public class BGGeolocationConfig: BGConfigModuleBase {

    @objc public var desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest
    @objc public var distanceFilter: CLLocationDistance = 10.0
    @objc public var stationaryRadius: CLLocationDistance = 25.0
    @objc public var locationTimeout: Double = 60.0
    @objc public var stopTimeout: Double = 5.0
    @objc public var stopAfterElapsedMinutes: Double = 0
    @objc public var activityType: CLActivityType = .automotiveNavigation
    @objc public var pausesLocationUpdatesAutomatically: Bool = false
    @objc public var showsBackgroundLocationIndicator: Bool = false
    @objc public var useSignificantChangesOnly: Bool = false
    // When true, the engine never powers GPS down to the stationary state — it
    // keeps continuous location updates running for the whole tracking session.
    // Combined with showsBackgroundLocationIndicator this is the "ride app"
    // behavior: the app stays alive in the background (location indicator shown)
    // and tracks continuously instead of relying on motion/region wakeups.
    // Higher battery cost; far more reliable background tracking.
    @objc public var disableStopDetection: Bool = false
    // Motion-gated battery saver. When false, full-power GPS runs ONLY while the
    // user is moving: the engine auto-enables continuous GPS on motion onset and
    // powers it down again when the user stops (overriding disableStopDetection
    // keep-alive). While stationary it relies on low-power motion detection,
    // significant-location-change / region relaunch, and APNs location pushes.
    // When true, GPS tracks continuously regardless of motion. Default true.
    @objc public var continuousLocationUpdates: Bool = true
    @objc public var locationAuthorizationRequest: String = "Always"
    @objc public var locationAuthorizationAlert: [String: String] = [:]
    @objc public var disableLocationAuthorizationAlert: Bool = false
    @objc public var geofenceProximityRadius: CLLocationDistance = 1000.0
    @objc public var geofenceInitialTriggerEntry: Bool = true
    @objc public var enableTimestampMeta: Bool = false
    @objc public var disableElasticity: Bool = false
    @objc public var elasticityMultiplier: Double = 1.0
    @objc public var filter: BGLocationFilterConfig?

    @objc public class func activityType(fromString s: String) -> CLActivityType {
        switch s.lowercased() {
        case "automotive_navigation", "automotivenavigation": return .automotiveNavigation
        case "fitness": return .fitness
        case "other_navigation", "othernavigation": return .otherNavigation
        case "other": return .other
        default: return .other
        }
    }

    @objc public class func string(forActivityType type: CLActivityType) -> String {
        switch type {
        case .automotiveNavigation: return "automotive_navigation"
        case .fitness: return "fitness"
        case .otherNavigation: return "other_navigation"
        case .other: return "other"
        default: return "other"
        }
    }

    @objc public class func decodeDesiredAccuracy(_ value: Any?) -> CLLocationAccuracy {
        if let n = value as? NSNumber {
            let d = n.doubleValue
            switch d {
            case -1: return kCLLocationAccuracyBestForNavigation
            case -2: return kCLLocationAccuracyBest
            case 10: return kCLLocationAccuracyNearestTenMeters
            case 100: return kCLLocationAccuracyHundredMeters
            case 1000: return kCLLocationAccuracyKilometer
            case 3000: return kCLLocationAccuracyThreeKilometers
            default: return d
            }
        }
        return kCLLocationAccuracyBest
    }

    @objc public override func applyDefaults() {
        desiredAccuracy = kCLLocationAccuracyBest
        distanceFilter = 10.0
        stationaryRadius = 25.0
        locationTimeout = 60.0
        stopTimeout = 5.0
        stopAfterElapsedMinutes = 0
        activityType = .automotiveNavigation
        pausesLocationUpdatesAutomatically = false
        showsBackgroundLocationIndicator = false
        useSignificantChangesOnly = false
        disableStopDetection = false
        continuousLocationUpdates = true
        locationAuthorizationRequest = "Always"
        disableLocationAuthorizationAlert = false
        geofenceProximityRadius = 1000.0
        geofenceInitialTriggerEntry = true
        enableTimestampMeta = false
        disableElasticity = false
        elasticityMultiplier = 1.0
    }

    @objc public var requestsAlwaysAuthorization: Bool {
        return locationAuthorizationRequest == "Always"
    }

    @objc public var usesHighAccuracyGPS: Bool {
        return desiredAccuracy <= kCLLocationAccuracyNearestTenMeters
    }

    @objc public var hasValidGeofenceProximityRadius: Bool {
        return geofenceProximityRadius > 0
    }

    @objc public func getLocationAuthorizationAlertStrings() -> [String: String] {
        return locationAuthorizationAlert
    }

    @objc public override func propertySpecs() -> [BGPropertySpecImpl] {
        return [
            BGPropertySpec(name: "desiredAccuracy", type: "double"),
            BGPropertySpec(name: "distanceFilter", type: "double"),
            BGPropertySpec(name: "stationaryRadius", type: "double"),
            BGPropertySpec(name: "locationTimeout", type: "double"),
            BGPropertySpec(name: "stopTimeout", type: "double"),
            BGPropertySpec(name: "stopAfterElapsedMinutes", type: "double"),
            BGPropertySpec(name: "activityType", type: "string"),
            BGPropertySpec(name: "pausesLocationUpdatesAutomatically", type: "bool"),
            BGPropertySpec(name: "showsBackgroundLocationIndicator", type: "bool"),
            BGPropertySpec(name: "useSignificantChangesOnly", type: "bool"),
            BGPropertySpec(name: "disableStopDetection", type: "bool"),
            BGPropertySpec(name: "continuousLocationUpdates", type: "bool"),
            BGPropertySpec(name: "locationAuthorizationRequest", type: "string"),
            BGPropertySpec(name: "disableLocationAuthorizationAlert", type: "bool"),
            BGPropertySpec(name: "geofenceProximityRadius", type: "double"),
            BGPropertySpec(name: "geofenceInitialTriggerEntry", type: "bool"),
            BGPropertySpec(name: "enableTimestampMeta", type: "bool"),
            BGPropertySpec(name: "disableElasticity", type: "bool"),
            BGPropertySpec(name: "elasticityMultiplier", type: "double")
        ]
    }

    @objc public override func validateConfiguration() -> Bool {
        return true
    }

    @objc public override var description: String {
        return "<BGGeolocationConfig desiredAccuracy=\(desiredAccuracy) distanceFilter=\(distanceFilter) stationaryRadius=\(stationaryRadius)>"
    }
}
