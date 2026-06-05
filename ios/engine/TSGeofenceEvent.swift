import Foundation
import CoreLocation

@objc public final class TSGeofenceEvent: NSObject {

    @objc public private(set) var identifier: String
    @objc public private(set) var action: String
    @objc public private(set) var timestamp: Date?
    @objc public private(set) var geofence: TSGeofence?
    @objc public private(set) var location: Any?
    @objc public private(set) var extras: [AnyHashable: Any]?

    @objc public init(identifier: String?,
                       action: String?,
                       timestamp: Date?,
                       geofence: TSGeofence?,
                       location: Any?,
                       extras: [AnyHashable: Any]?) {
        self.identifier = identifier ?? ""
        self.action = action ?? ""
        self.timestamp = timestamp
        self.geofence = geofence
        self.location = location ?? [AnyHashable: Any]()
        self.extras = extras
        super.init()
    }

    @objc public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [:]
        dict["identifier"] = identifier
        dict["action"] = action
        if let timestamp = timestamp {
            dict["timestamp"] = TSDateUtils.iso8601String(from: timestamp)
        }
        dict["geofence"] = geofence?.toDictionary()
        dict["location"] = location
        if let extras = extras {
            dict["extras"] = extras
        }
        return dict
    }
}
