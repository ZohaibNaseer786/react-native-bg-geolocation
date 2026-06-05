import Foundation
import CoreLocation

@objc public class TSSingleLocationRequest: NSObject {

    @objc public var type: String = "single"
    @objc public var maximumAge: Double = 0
    @objc public var timeout: Double = 30
    @objc public var desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest
    @objc public var allowStale: Bool = false
    @objc public var samples: Int = 1
    @objc public var label: String?
    @objc public var persist: Bool = false
    @objc public var extras: [AnyHashable: Any]?
    @objc public var success: ((Any?) -> Void)?
    @objc public var failure: ((Int) -> Void)?
    @objc public var requestId: String = UUID().uuidString

    @objc public override init() {
        super.init()
    }

    @objc public init(
        type: String,
        maximumAge: Double,
        timeout: Double,
        desiredAccuracy: CLLocationAccuracy,
        allowStale: Bool,
        samples: Int,
        label: String?,
        persist: Bool,
        extras: [AnyHashable: Any]?,
        success: @escaping (Any?) -> Void,
        failure: @escaping (Int) -> Void
    ) {
        self.type = type
        self.maximumAge = maximumAge
        self.timeout = timeout
        self.desiredAccuracy = desiredAccuracy
        self.allowStale = allowStale
        self.samples = samples
        self.label = label
        self.persist = persist
        self.extras = extras
        self.success = success
        self.failure = failure
        super.init()
    }
}
