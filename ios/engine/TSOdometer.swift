import Foundation
import CoreLocation

@objc public class TSOdometer: NSObject {

    private static var _sharedInstance: TSOdometer?
    private static let lock = NSLock()

    @objc public var value: Double = 0
    private var lastLocation: CLLocation?
    private let userDefaultsKey = "TSLocationManager_odometer"

    @objc public class func sharedInstance() -> TSOdometer {
        lock.lock()
        defer { lock.unlock() }
        if _sharedInstance == nil {
            _sharedInstance = TSOdometer()
        }
        return _sharedInstance!
    }

    @objc public override init() {
        super.init()
        value = UserDefaults.standard.double(forKey: userDefaultsKey)
    }

    @objc public func addDistance(from location: CLLocation) -> Double {
        guard let last = lastLocation else {
            lastLocation = location
            return value
        }
        let delta = location.distance(from: last)
        value += delta
        lastLocation = location
        persist()
        return value
    }

    @objc public func setOdometer(_ newValue: Double, location: CLLocation?) {
        value = newValue
        lastLocation = location
        persist()
    }

    @objc public func reset() {
        value = 0
        lastLocation = nil
        persist()
    }

    @objc public func getOdometer() -> Double {
        return value
    }

    @objc public func setLastLocation(_ location: CLLocation?) {
        lastLocation = location
    }

    @objc public func lastKnownLocation() -> CLLocation? {
        return lastLocation
    }

    private func persist() {
        UserDefaults.standard.set(value, forKey: userDefaultsKey)
    }
}
