import Foundation
import CoreLocation

public typealias BGLocationSuccessBlock = (_ location: Any?) -> Void
public typealias BGLocationFailureBlock = (_ code: Int) -> Void

@objc public class BGCurrentPositionRequest: NSObject {

    @objc public var requestId: String = UUID().uuidString
    @objc public var type: String = "current_position"
    @objc public var maximumAge: Double = 0
    @objc public var timeout: Double = 30
    @objc public var desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest
    @objc public var allowStale: Bool = false
    @objc public var samples: Int = 3
    @objc public var label: String?
    @objc public var persist: Bool = true
    @objc public var extras: [AnyHashable: Any]?
    @objc public var success: BGLocationSuccessBlock?
    @objc public var failure: BGLocationFailureBlock?

    @objc public class func request(
        success: @escaping BGLocationSuccessBlock,
        failure: @escaping BGLocationFailureBlock
    ) -> BGCurrentPositionRequest {
        return BGCurrentPositionRequest(
            type: "current_position",
            maximumAge: 0,
            timeout: 30,
            desiredAccuracy: kCLLocationAccuracyBest,
            allowStale: false,
            samples: 3,
            label: nil,
            persist: true,
            extras: nil,
            success: success,
            failure: failure
        )
    }

    @objc public class func request(
        type: String,
        success: @escaping BGLocationSuccessBlock,
        failure: @escaping BGLocationFailureBlock
    ) -> BGCurrentPositionRequest {
        return BGCurrentPositionRequest(
            type: type,
            maximumAge: 0,
            timeout: 30,
            desiredAccuracy: kCLLocationAccuracyBest,
            allowStale: false,
            samples: 3,
            label: nil,
            persist: true,
            extras: nil,
            success: success,
            failure: failure
        )
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
        success: @escaping BGLocationSuccessBlock,
        failure: @escaping BGLocationFailureBlock
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
