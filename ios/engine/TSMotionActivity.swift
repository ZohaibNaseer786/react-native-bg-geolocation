import Foundation

@objc public final class TSMotionActivity: NSObject {

    @objc public var type: String = "unknown"
    @objc public var confidence: Int = 0
    @objc public var name: String { return type }

    @objc public override convenience init() {
        self.init(type: "unknown", confidence: 0)
    }

    @objc public init(type: String, confidence: Int) {
        super.init()
        self.type = type
        self.confidence = confidence
    }

    // Integer-based type value for legacy ObjC compatibility
    @objc public var typeCode: Int {
        switch type {
        case "still": return 1
        case "on_foot": return 2
        case "running": return 3
        case "in_vehicle": return 4
        case "on_bicycle": return 5
        case "moving": return 7
        default: return 6
        }
    }
}
