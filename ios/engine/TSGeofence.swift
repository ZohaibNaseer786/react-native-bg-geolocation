import Foundation
import CoreLocation

@objc public class TSGeofence: NSObject {

    @objc public var identifier: String = ""
    @objc public var latitude: CLLocationDegrees = 0
    @objc public var longitude: CLLocationDegrees = 0
    @objc public var radius: CLLocationDistance = 200
    @objc public var notifyOnEntry: Bool = true
    @objc public var notifyOnExit: Bool = true
    @objc public var notifyOnDwell: Bool = false
    @objc public var loiteringDelay: Double = 0
    @objc public var extras: [String: Any]?
    @objc public var vertices: [[Double]] = []

    @objc public var entryState: String = "UNKNOWN"
    @objc public var stateUpdatedAt: Date?
    @objc public var hits: Int = 0
    @objc public var isLoitering: Bool = false
    @objc public var isMonitoring: Bool = false
    @objc public var loiteringRegion: CLCircularRegion?
    @objc public var loiteringTransition: String?
    @objc public var request: Any?
    @objc public var cancelRequest: (() -> Void)?
    @objc public var currentPolygonHits: Int = 0
    @objc public var desiredPolygonHits: Int = 0

    @objc public class func circle(
        withIdentifier identifier: String,
        radius: CLLocationDistance,
        latitude: CLLocationDegrees,
        longitude: CLLocationDegrees,
        notifyOnEntry: Bool,
        notifyOnExit: Bool,
        notifyOnDwell: Bool,
        loiteringDelay: Double,
        extras: [String: Any]?
    ) -> TSGeofence {
        let g = TSGeofence()
        g.identifier = identifier
        g.radius = radius
        g.latitude = latitude
        g.longitude = longitude
        g.notifyOnEntry = notifyOnEntry
        g.notifyOnExit = notifyOnExit
        g.notifyOnDwell = notifyOnDwell
        g.loiteringDelay = loiteringDelay
        g.extras = extras
        return g
    }

    @objc public class func polygon(
        withIdentifier identifier: String,
        vertices: [[Double]],
        notifyOnEntry: Bool,
        notifyOnExit: Bool,
        notifyOnDwell: Bool,
        loiteringDelay: Double,
        extras: [String: Any]?
    ) -> TSGeofence {
        let g = TSGeofence()
        g.identifier = identifier
        g.vertices = vertices
        g.notifyOnEntry = notifyOnEntry
        g.notifyOnExit = notifyOnExit
        g.notifyOnDwell = notifyOnDwell
        g.loiteringDelay = loiteringDelay
        g.extras = extras
        return g
    }

    @objc public init(
        identifier: String,
        radius: CLLocationDistance,
        latitude: CLLocationDegrees,
        longitude: CLLocationDegrees,
        notifyOnEntry: Bool,
        notifyOnExit: Bool,
        notifyOnDwell: Bool,
        loiteringDelay: Double
    ) {
        self.identifier = identifier
        self.radius = radius
        self.latitude = latitude
        self.longitude = longitude
        self.notifyOnEntry = notifyOnEntry
        self.notifyOnExit = notifyOnExit
        self.notifyOnDwell = notifyOnDwell
        self.loiteringDelay = loiteringDelay
        super.init()
    }

    @objc public init(
        identifier: String,
        radius: CLLocationDistance,
        latitude: CLLocationDegrees,
        longitude: CLLocationDegrees,
        notifyOnEntry: Bool,
        notifyOnExit: Bool,
        notifyOnDwell: Bool,
        loiteringDelay: Double,
        extras: [String: Any]?,
        vertices: [[Double]]
    ) {
        self.identifier = identifier
        self.radius = radius
        self.latitude = latitude
        self.longitude = longitude
        self.notifyOnEntry = notifyOnEntry
        self.notifyOnExit = notifyOnExit
        self.notifyOnDwell = notifyOnDwell
        self.loiteringDelay = loiteringDelay
        self.extras = extras
        self.vertices = vertices
        super.init()
    }

    @objc public init(
        identifier: String,
        radius: CLLocationDistance,
        latitude: CLLocationDegrees,
        longitude: CLLocationDegrees,
        notifyOnEntry: Bool,
        notifyOnExit: Bool,
        notifyOnDwell: Bool,
        loiteringDelay: Double,
        extras: [String: Any]?,
        vertices: [[Double]],
        entryState: String,
        stateUpdatedAt: Date?,
        hits: Int
    ) {
        self.identifier = identifier
        self.radius = radius
        self.latitude = latitude
        self.longitude = longitude
        self.notifyOnEntry = notifyOnEntry
        self.notifyOnExit = notifyOnExit
        self.notifyOnDwell = notifyOnDwell
        self.loiteringDelay = loiteringDelay
        self.extras = extras
        self.vertices = vertices
        self.entryState = entryState
        self.stateUpdatedAt = stateUpdatedAt
        self.hits = hits
        super.init()
    }

    @objc public override init() {
        super.init()
    }

    @objc public var isPolygon: Bool {
        return !vertices.isEmpty
    }

    @objc public var exitMEC: CLCircularRegion? {
        guard !isPolygon else { return nil }
        let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        return CLCircularRegion(center: center, radius: radius, identifier: identifier)
    }

    @objc public func startMonitoring(withLocationManager manager: CLLocationManager, prefix: String) {
        guard !isPolygon else {
            startMonitoringPolygon()
            return
        }
        let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let region = CLCircularRegion(center: center, radius: radius, identifier: "\(prefix)\(identifier)")
        region.notifyOnEntry = notifyOnEntry
        region.notifyOnExit = notifyOnExit
        manager.startMonitoring(for: region)
        isMonitoring = true
    }

    @objc public func startMonitoringPolygon() {
        isMonitoring = true
    }

    @objc public func stopMonitoringPolygon() {
        isMonitoring = false
    }

    @objc public func startLoitering() {
        isLoitering = true
    }

    @objc public func cancelLoitering() {
        isLoitering = false
    }

    @objc public func cancelLocationRequest() {
        cancelRequest?()
        cancelRequest = nil
    }

    @objc public func cancel() {
        cancelLocationRequest()
        isMonitoring = false
    }

    @objc public func fireEvent(_ action: String, location: CLLocation?) {
        NotificationCenter.default.post(
            name: NSNotification.Name("TSGeofenceEvent"),
            object: self,
            userInfo: ["action": action, "location": location as Any]
        )
    }

    @objc public func persistState() {
    }

    @objc public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "identifier": identifier,
            "latitude": latitude,
            "longitude": longitude,
            "radius": radius,
            "notifyOnEntry": notifyOnEntry,
            "notifyOnExit": notifyOnExit,
            "notifyOnDwell": notifyOnDwell,
            "loiteringDelay": loiteringDelay
        ]
        if let extras = extras { dict["extras"] = extras }
        if !vertices.isEmpty { dict["vertices"] = vertices }
        return dict
    }

    @objc public override var description: String {
        return "<TSGeofence id=\(identifier) lat=\(latitude) lon=\(longitude) radius=\(radius)>"
    }
}
