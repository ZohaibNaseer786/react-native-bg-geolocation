import Foundation

@objc public final class BGActivityChangeEvent: NSObject {

    @objc public private(set) var confidence: Int
    @objc public private(set) var activity: String

    @objc public init(activityName: String?, confidence: Int) {
        self.confidence = confidence
        self.activity = activityName ?? "unknown"
        super.init()
    }

    @objc public func toDictionary() -> [String: Any] {
        return [
            "activity": activity,
            "confidence": confidence
        ]
    }
}
