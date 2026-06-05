import Foundation
import CoreLocation

@objc public class TSKalmanFilter: NSObject {

    @objc public var Q: Double = 3.0
    @objc public var R: Double = 15.0
    @objc public var profile: String = "default"
    @objc public var debug: Bool = false

    private var P: Double = 1.0
    private var K: Double = 0.0
    private var estimate: CLLocation?
    private var lastProcessed: CLLocation?
    private var diagnostics: [[String: Any]] = []

    @objc public init(withInitialEstimate location: CLLocation) {
        self.estimate = location
        super.init()
    }

    @objc public override init() {
        super.init()
    }

    @objc public func configureForSpeed(_ speed: CLLocationSpeed,
                                        accuracy: CLLocationAccuracy,
                                        distanceFilter: CLLocationDistance) {
        Q = max(1.0, min(speed * 0.1, 10.0))
        R = max(accuracy * 0.5, 5.0)
    }

    @objc public func process(_ location: CLLocation, accuracy: CLLocationAccuracy) -> CLLocation {
        guard let current = estimate else {
            estimate = location
            return location
        }

        let dt = location.timestamp.timeIntervalSince(current.timestamp)
        guard dt > 0 else { return current }

        P = P + Q * dt
        K = P / (P + R)
        P = (1.0 - K) * P

        let lat = current.coordinate.latitude + K * (location.coordinate.latitude - current.coordinate.latitude)
        let lon = current.coordinate.longitude + K * (location.coordinate.longitude - current.coordinate.longitude)
        let alt = current.altitude + K * (location.altitude - current.altitude)

        let smoothed = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            altitude: alt,
            horizontalAccuracy: location.horizontalAccuracy,
            verticalAccuracy: location.verticalAccuracy,
            timestamp: location.timestamp
        )

        estimate = smoothed
        lastProcessed = location

        if debug {
            diagnostics.append([
                "timestamp": location.timestamp,
                "raw": ["lat": location.coordinate.latitude, "lon": location.coordinate.longitude],
                "smoothed": ["lat": lat, "lon": lon],
                "K": K, "P": P
            ])
        }

        return smoothed
    }

    @objc public func reset(withValue location: CLLocation, coldStart: Bool) {
        estimate = location
        P = coldStart ? 1.0 : P
        K = 0.0
        diagnostics = []
    }

    @objc public func tuning() -> [String: Double] {
        return ["Q": Q, "R": R]
    }

    @objc public func setTuning(_ tuning: [String: Double]) {
        if let q = tuning["Q"] { Q = q }
        if let r = tuning["R"] { R = r }
    }

    @objc public func getDiagnostics() -> [[String: Any]] {
        return diagnostics
    }

    @objc public func exportDiagnosticsToCSV(_ path: String) {
        var csv = "timestamp,raw_lat,raw_lon,smoothed_lat,smoothed_lon,K,P\n"
        for entry in diagnostics {
            let ts = (entry["timestamp"] as? Date)?.timeIntervalSince1970 ?? 0
            let raw = entry["raw"] as? [String: Double] ?? [:]
            let smoothed = entry["smoothed"] as? [String: Double] ?? [:]
            let k = entry["K"] as? Double ?? 0
            let p = entry["P"] as? Double ?? 0
            csv += "\(ts),\(raw["lat"] ?? 0),\(raw["lon"] ?? 0),\(smoothed["lat"] ?? 0),\(smoothed["lon"] ?? 0),\(k),\(p)\n"
        }
        try? csv.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
