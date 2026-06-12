import Foundation

@objc public final class BGLocationStreamEvent: NSObject {

    @objc public private(set) var streamId: Int
    @objc public private(set) var locationEvent: BGLocationEvent?

    @objc public init(streamId: Int, locationEvent: BGLocationEvent?) {
        self.streamId = streamId
        self.locationEvent = locationEvent
        super.init()
    }

    @objc public func toDictionary() -> [String: Any] {
        let dict = NSMutableDictionary()
        if let locationEvent = locationEvent {
            dict["location"] = locationEvent.toDictionary()
        }
        dict["streamId"] = streamId
        return dict as! [String: Any]
    }

    public override var description: String {
        return String(format: "<BGLocationStreamEvent id=%ld event=%@>",
                      streamId, String(describing: locationEvent))
    }
}
