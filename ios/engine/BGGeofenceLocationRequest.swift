import Foundation
import CoreLocation

@objc public class BGGeofenceLocationRequest: BGSingleLocationRequest {

    @objc public var geofenceEvent: BGGeofenceEvent?

    @objc public class func request(
        event: BGGeofenceEvent,
        maximumAge: Double,
        timeout: Double,
        desiredAccuracy: CLLocationAccuracy,
        allowStale: Bool,
        samples: Int,
        label: String?,
        persist: Bool,
        success: @escaping (Any?) -> Void,
        failure: @escaping (Int) -> Void
    ) -> BGGeofenceLocationRequest {
        let req = BGGeofenceLocationRequest()
        req.geofenceEvent = event
        req.maximumAge = maximumAge
        req.timeout = timeout
        req.desiredAccuracy = desiredAccuracy
        req.allowStale = allowStale
        req.samples = samples
        req.label = label
        req.persist = persist
        req.success = success
        req.failure = failure
        req.type = "geofence"
        return req
    }

    @objc public init(
        event: BGGeofenceEvent,
        maximumAge: Double,
        timeout: Double,
        desiredAccuracy: CLLocationAccuracy,
        allowStale: Bool,
        samples: Int,
        label: String?,
        persist: Bool,
        success: @escaping (Any?) -> Void,
        failure: @escaping (Int) -> Void
    ) {
        super.init()
        self.geofenceEvent = event
        self.maximumAge = maximumAge
        self.timeout = timeout
        self.desiredAccuracy = desiredAccuracy
        self.allowStale = allowStale
        self.samples = samples
        self.label = label
        self.persist = persist
        self.success = success
        self.failure = failure
        self.type = "geofence"
    }

    @objc public override init() {
        super.init()
        self.type = "geofence"
    }

    @objc public func copy(with zone: NSZone? = nil) -> Any {
        let copy = BGGeofenceLocationRequest()
        copy.geofenceEvent = geofenceEvent
        copy.maximumAge = maximumAge
        copy.timeout = timeout
        copy.desiredAccuracy = desiredAccuracy
        copy.allowStale = allowStale
        copy.samples = samples
        copy.label = label
        copy.persist = persist
        copy.success = success
        copy.failure = failure
        return copy
    }

    @objc public func didComplete(withLocation location: CLLocation) {
        success?(location)
    }

    public func setType(_ type: String) {
        self.type = type
    }

    @objc public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = ["type": type]
        if let event = geofenceEvent { dict["geofenceEvent"] = event.toDictionary() }
        return dict
    }
}
