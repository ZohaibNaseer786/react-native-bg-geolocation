import Foundation
import CoreLocation

@objc public class BGStreamLocationRequest: NSObject {

    @objc public var streamId: Int = 0
    @objc public var interval: Double = 1000.0
    @objc public var desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest
    @objc public var timeout: Double = 60.0
    @objc public var persist: Bool = true
    @objc public var extras: [AnyHashable: Any]?
    @objc public var label: String?
    @objc public var success: ((Any?) -> Void)?
    @objc public var failure: ((Int) -> Void)?

    @objc public override init() {
        super.init()
    }

    @objc public init(
        streamId: Int,
        interval: Double,
        desiredAccuracy: CLLocationAccuracy,
        timeout: Double,
        persist: Bool,
        extras: [AnyHashable: Any]?,
        label: String?,
        success: @escaping (Any?) -> Void,
        failure: @escaping (Int) -> Void
    ) {
        self.streamId = streamId
        self.interval = interval
        self.desiredAccuracy = desiredAccuracy
        self.timeout = timeout
        self.persist = persist
        self.extras = extras
        self.label = label
        self.success = success
        self.failure = failure
        super.init()
    }
}
