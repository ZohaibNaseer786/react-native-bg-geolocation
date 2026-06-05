import Foundation

@objc public final class TSCallback: NSObject {

    @objc public var success: Any?
    @objc public var failure: Any?
    @objc public private(set) var options: Any?

    @objc public init(success: Any?, failure: Any?) {
        self.success = success
        self.failure = failure
        super.init()
    }

    @objc public convenience init(success: Any?, failure: Any?, options: Any?) {
        self.init(success: success, failure: failure)
        self.options = options
    }
}
