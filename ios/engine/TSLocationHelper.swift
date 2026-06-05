import Foundation
import CoreLocation

@objc public class TSLocationHelper: NSObject {

    @objc public class func isAccurate(
        _ location: CLLocation,
        desiredAccuracy: CLLocationAccuracy
    ) -> Bool {
        guard location.horizontalAccuracy >= 0 else { return false }
        if desiredAccuracy == kCLLocationAccuracyBest ||
           desiredAccuracy == kCLLocationAccuracyBestForNavigation {
            return location.horizontalAccuracy < 100
        }
        return location.horizontalAccuracy <= desiredAccuracy
    }

    @objc public class func locationAge(_ location: CLLocation) -> TimeInterval {
        return Date().timeIntervalSince(location.timestamp)
    }

    @objc public class func sameTimestamp(_ a: CLLocation, as b: CLLocation) -> Bool {
        return abs(a.timestamp.timeIntervalSince(b.timestamp)) < 0.001
    }

    @objc public class func pickBestLocation(
        between a: CLLocation?,
        and b: CLLocation?,
        desiredAccuracy: CLLocationAccuracy
    ) -> CLLocation? {
        guard let a = a else { return b }
        guard let b = b else { return a }
        if a.horizontalAccuracy < 0 { return b }
        if b.horizontalAccuracy < 0 { return a }
        return a.horizontalAccuracy <= b.horizontalAccuracy ? a : b
    }

    @objc public class func resolveLocation(
        withNow now: Date,
        desiredAccuracy: CLLocationAccuracy,
        allowStale: Bool,
        maximumAgeSeconds: Double,
        bestLocation: CLLocation?,
        mostAccurateLocation: CLLocation?,
        freshestLocation: CLLocation?
    ) -> CLLocation? {
        let candidates = [bestLocation, mostAccurateLocation, freshestLocation].compactMap { $0 }
        let fresh = candidates.filter { now.timeIntervalSince($0.timestamp) <= maximumAgeSeconds }
        if allowStale || fresh.isEmpty {
            return candidates.min(by: { $0.horizontalAccuracy < $1.horizontalAccuracy })
        }
        return fresh.min(by: { $0.horizontalAccuracy < $1.horizontalAccuracy })
    }
}
