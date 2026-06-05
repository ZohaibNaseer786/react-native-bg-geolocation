import Foundation
import CoreLocation

@objc public class TSGeofenceDAO: NSObject {

    private static var _sharedInstance: TSGeofenceDAO?
    private static let lock = NSLock()
    private var geofences: [String: TSGeofence] = [:]
    private let daLock = NSLock()

    @objc public class func sharedInstance() -> TSGeofenceDAO {
        lock.lock()
        defer { lock.unlock() }
        if _sharedInstance == nil {
            _sharedInstance = TSGeofenceDAO()
        }
        return _sharedInstance!
    }

    @objc public override init() {
        super.init()
    }

    @objc public func all() -> [TSGeofence] {
        daLock.lock()
        defer { daLock.unlock() }
        return Array(geofences.values)
    }

    @objc public func all(withLocking lock: Bool) -> [TSGeofence] {
        return all()
    }

    @objc public func count() -> Int {
        daLock.lock()
        defer { daLock.unlock() }
        return geofences.count
    }

    @objc public func maxRadius() -> CLLocationDistance {
        daLock.lock()
        defer { daLock.unlock() }
        return geofences.values.map { $0.radius }.max() ?? 0
    }

    @objc public func find(_ identifier: String) -> TSGeofence? {
        daLock.lock()
        defer { daLock.unlock() }
        return geofences[identifier]
    }

    @objc public func exists(_ identifier: String) -> Bool {
        daLock.lock()
        defer { daLock.unlock() }
        return geofences[identifier] != nil
    }

    @objc public func exists(_ db: Any?, identifier: String) -> Bool {
        return exists(identifier)
    }

    @objc public func create(_ geofence: TSGeofence) -> Bool {
        daLock.lock()
        geofences[geofence.identifier] = geofence
        daLock.unlock()
        return true
    }

    @objc public func createAll(_ fences: [TSGeofence]) {
        daLock.lock()
        for g in fences { geofences[g.identifier] = g }
        daLock.unlock()
    }

    @objc public func destroy(_ identifier: String) -> Bool {
        daLock.lock()
        let existed = geofences.removeValue(forKey: identifier) != nil
        daLock.unlock()
        return existed
    }

    @objc public func destroyAll() {
        daLock.lock()
        geofences.removeAll()
        daLock.unlock()
    }

    @objc public func doInsert(_ db: Any?, geofence: TSGeofence) -> Bool {
        return create(geofence)
    }

    @objc public func hydrate(_ row: [String: Any]) -> TSGeofence? {
        guard let id = row["identifier"] as? String else { return nil }
        let g = TSGeofence()
        g.identifier = id
        g.latitude = row["latitude"] as? CLLocationDegrees ?? 0
        g.longitude = row["longitude"] as? CLLocationDegrees ?? 0
        g.radius = row["radius"] as? CLLocationDistance ?? 200
        g.notifyOnEntry = row["notify_on_entry"] as? Bool ?? true
        g.notifyOnExit = row["notify_on_exit"] as? Bool ?? true
        g.notifyOnDwell = row["notify_on_dwell"] as? Bool ?? false
        g.loiteringDelay = row["loitering_delay"] as? Double ?? 0
        g.entryState = row["entry_state"] as? String ?? "UNKNOWN"
        g.hits = row["hits"] as? Int ?? 0
        if let extrasStr = row["extras"] as? String {
            g.extras = decodeExtras(extrasStr)
        }
        if let vertStr = row["vertices"] as? String {
            g.vertices = decodeVertices(vertStr)
        }
        return g
    }

    @objc public func decodeExtras(_ json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    @objc public func decodeVertices(_ json: String) -> [[Double]] {
        guard let data = json.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[Double]] else { return [] }
        return arr
    }

    @objc public func allWithinRadius(
        _ radius: CLLocationDistance,
        latitude: CLLocationDegrees,
        longitude: CLLocationDegrees,
        limit: Int
    ) -> [TSGeofence] {
        let center = CLLocation(latitude: latitude, longitude: longitude)
        daLock.lock()
        var results = geofences.values.filter {
            let loc = CLLocation(latitude: $0.latitude, longitude: $0.longitude)
            return center.distance(from: loc) <= radius
        }
        daLock.unlock()
        if limit > 0 { results = Array(results.prefix(limit)) }
        return results
    }

    @objc public func updateState(
        forIdentifier identifier: String,
        entryState: String,
        hits: Int
    ) {
        daLock.lock()
        geofences[identifier]?.entryState = entryState
        geofences[identifier]?.hits = hits
        daLock.unlock()
    }
}
