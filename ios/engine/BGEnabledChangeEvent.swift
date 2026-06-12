import Foundation

@objc public final class BGEnabledChangeEvent: NSObject {

    @objc public private(set) var enabled: Bool

    @objc public init(enabled: Bool) {
        self.enabled = enabled
        super.init()
    }
}
