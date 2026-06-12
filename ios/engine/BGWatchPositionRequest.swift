import Foundation
import CoreLocation

public typealias BGWatchPositionSuccessBlock = (Any?) -> Void
public typealias BGWatchPositionFailureBlock = (Int) -> Void

@objc public final class BGWatchPositionRequest: NSObject {

    @objc public var persist: Bool
    @objc public var desiredAccuracy: CLLocationAccuracy
    @objc public private(set) var interval: Double
    @objc public var extras: [AnyHashable: Any]?
    @objc public var timeout: Double
    @objc public var success: BGWatchPositionSuccessBlock?
    @objc public var failure: BGWatchPositionFailureBlock?

    @objc public class func request(success: @escaping BGWatchPositionSuccessBlock,
                                     failure: @escaping BGWatchPositionFailureBlock) -> BGWatchPositionRequest {
        let config = BGConfig.sharedInstance()
        let geo = config.geolocation
        return BGWatchPositionRequest(interval: 60000.0,
                                      timeout: geo.locationTimeout,
                                      persist: config.enabled,
                                      extras: nil,
                                      success: success,
                                      failure: failure)
    }

    @objc public class func request(interval: Double,
                                     success: @escaping BGWatchPositionSuccessBlock,
                                     failure: @escaping BGWatchPositionFailureBlock) -> BGWatchPositionRequest {
        let config = BGConfig.sharedInstance()
        let geo = config.geolocation
        return BGWatchPositionRequest(interval: interval,
                                      timeout: geo.locationTimeout,
                                      persist: config.enabled,
                                      extras: nil,
                                      success: success,
                                      failure: failure)
    }

    @objc public init(interval: Double,
                       timeout: Double,
                       persist: Bool,
                       extras: [AnyHashable: Any]?,
                       success: @escaping BGWatchPositionSuccessBlock,
                       failure: @escaping BGWatchPositionFailureBlock) {
        self.desiredAccuracy = kCLLocationAccuracyBest
        self.interval = max(interval, 1000.0)
        self.timeout = max(timeout, 0.0)
        self.persist = persist
        self.extras = extras
        self.success = success
        self.failure = failure
        super.init()
    }

    public func setInterval(_ newValue: Double) {
        objc_sync_enter(self)
        interval = max(newValue, 1000.0)
        objc_sync_exit(self)
    }
}
