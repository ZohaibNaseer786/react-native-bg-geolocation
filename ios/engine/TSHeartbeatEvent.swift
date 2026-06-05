import Foundation
import CoreLocation

@objc public final class TSHeartbeatEvent: NSObject {

    @objc public private(set) var location: CLLocation?
    @objc public private(set) var data: [AnyHashable: Any]?

    @objc public init(location: CLLocation?) {
        super.init()
        guard let location = location else {
            self.location = nil
            self.data = nil
            return
        }
        let rebuilt = CLLocation(coordinate: location.coordinate,
                                 altitude: location.altitude,
                                 horizontalAccuracy: location.horizontalAccuracy,
                                 verticalAccuracy: location.verticalAccuracy,
                                 course: location.course,
                                 speed: location.speed,
                                 timestamp: location.timestamp)
        self.location = rebuilt
        let tsLocation = TSLocation(location: rebuilt, type: "heartbeat", extras: nil)
        self.data = tsLocation.toDictionary()
    }

    @objc public func toDictionary() -> [String: Any] {
        return ["location": data ?? NSNull()]
    }
}
