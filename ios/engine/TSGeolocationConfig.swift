import Foundation
import CoreLocation

@objc public class TSGeolocationConfig: TSConfigModuleBase {

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
    @objc public var locationAuthorizationRequest: String = "Always"
    @objc public var locationAuthorizationAlert: [String: String] = [:]
    @objc public var disableLocationAuthorizationAlert: Bool = false
    @objc public var geofenceProximityRadius: CLLocationDistance = 1000.0
    @objc public var geofenceInitialTriggerEntry: Bool = true
    @objc public var enableTimestampMeta: Bool = false
    @objc public var disableElasticity: Bool = false
    @objc public var elasticityMultiplier: Double = 1.0
    @objc public var filter: TSLocationFilterConfig?

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

    @objc public override func propertySpecs() -> [TSPropertySpecImpl] {
        return [
            TSPropertySpec(name: "desiredAccuracy", type: "double"),
            TSPropertySpec(name: "distanceFilter", type: "double"),
            TSPropertySpec(name: "stationaryRadius", type: "double"),
            TSPropertySpec(name: "locationTimeout", type: "double"),
            TSPropertySpec(name: "stopTimeout", type: "double"),
            TSPropertySpec(name: "stopAfterElapsedMinutes", type: "double"),
            TSPropertySpec(name: "activityType", type: "string"),
            TSPropertySpec(name: "pausesLocationUpdatesAutomatically", type: "bool"),
            TSPropertySpec(name: "showsBackgroundLocationIndicator", type: "bool"),
            TSPropertySpec(name: "useSignificantChangesOnly", type: "bool"),
            TSPropertySpec(name: "locationAuthorizationRequest", type: "string"),
            TSPropertySpec(name: "disableLocationAuthorizationAlert", type: "bool"),
            TSPropertySpec(name: "geofenceProximityRadius", type: "double"),
            TSPropertySpec(name: "geofenceInitialTriggerEntry", type: "bool"),
            TSPropertySpec(name: "enableTimestampMeta", type: "bool"),
            TSPropertySpec(name: "disableElasticity", type: "bool"),
            TSPropertySpec(name: "elasticityMultiplier", type: "double")
        ]
    }

    @objc public override func validateConfiguration() -> Bool {
        return true
    }

    @objc public override var description: String {
        return "<TSGeolocationConfig desiredAccuracy=\(desiredAccuracy) distanceFilter=\(distanceFilter) stationaryRadius=\(stationaryRadius)>"
    }
}
