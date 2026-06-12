import Foundation
import CoreLocation

@objc public class BGLocationEvent: NSObject {

    @objc public var location: CLLocation?
    @objc public var data: [String: Any]
    @objc public var event: String
    @objc public var isMoving: Bool
    @objc public var recordedAt: Date
    @objc public var timestamp: Date

    @objc public class func create(withTSLocation tsLocation: Any) -> BGLocationEvent {
        let event = BGLocationEvent()
        return event
    }

    @objc public init(locationDictionary: [String: Any], location: CLLocation?) {
        self.data = locationDictionary
        self.location = location
        self.event = locationDictionary["event"] as? String ?? ""
        self.isMoving = locationDictionary["is_moving"] as? Bool ?? false
        self.timestamp = Date()
        self.recordedAt = Date()
        super.init()
    }

    @objc public override init() {
        data = [:]
        event = ""
        isMoving = false
        timestamp = Date()
        recordedAt = Date()
        super.init()
    }

    @objc public func toDictionary() -> [String: Any] {
        var dict = data
        dict["event"] = event
        dict["is_moving"] = isMoving
        return dict
    }
}
