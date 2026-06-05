import Foundation

@objc public final class TSConnectivityChangeEvent: NSObject {

    @objc public private(set) var hasConnection: Bool

    @objc public init(hasConnection: Bool) {
        self.hasConnection = hasConnection
        super.init()
    }

    @objc public func toDictionary() -> [String: Any] {
        return ["connected": hasConnection]
    }
}
