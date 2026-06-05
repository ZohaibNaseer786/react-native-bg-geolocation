import Foundation
import CoreLocation

@objc public class TSLocationSatisfier: NSObject {

    @objc public var location: CLLocation
    @objc public var satisfied: Bool = false
    @objc public var cancel: (() -> Void)?

    @objc public init(location: CLLocation) {
        self.location = location
        super.init()
    }
}
