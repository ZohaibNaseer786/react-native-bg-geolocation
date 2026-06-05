import Foundation

@objc public final class TSLocationStreamEvent: NSObject {

    @objc public private(set) var streamId: Int
    @objc public private(set) var locationEvent: TSLocationEvent?

    @objc public init(streamId: Int, locationEvent: TSLocationEvent?) {
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
        return String(format: "<TSLocationStreamEvent id=%ld event=%@>",
                      streamId, String(describing: locationEvent))
    }
}
