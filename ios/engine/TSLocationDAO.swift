import Foundation
import CoreLocation

@objc public class TSLocationDAO: NSObject {

    private static var _sharedInstance: TSLocationDAO?
    private static let lock = NSLock()

    private var dbQueue: TSDatabaseQueue?
    private let accessQueue = DispatchQueue(label: "TSLocationDAO.access")

    @objc public class func sharedInstance() -> TSLocationDAO {
        lock.lock()
        defer { lock.unlock() }
        if _sharedInstance == nil {
            _sharedInstance = TSLocationDAO()
        }
        return _sharedInstance!
    }

    @objc public override init() {
        super.init()
        setupDatabase()
        registerConfigChangeHandlers()
    }

    private func setupDatabase() {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        guard let docPath = paths.first else { return }
        let dbPath = docPath.appendingPathComponent("TSLocationManager.db")
        dbQueue = TSDatabaseQueue(path: dbPath.path)
        dbQueue?.inDatabase { db in
            _ = db.executeUpdate("""
                CREATE TABLE IF NOT EXISTS locations (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    uuid TEXT UNIQUE NOT NULL,
                    timestamp REAL NOT NULL,
                    latitude REAL NOT NULL,
                    longitude REAL NOT NULL,
                    accuracy REAL,
                    altitude REAL,
                    speed REAL,
                    heading REAL,
                    odometer REAL,
                    is_moving INTEGER,
                    event TEXT,
                    activity_type TEXT,
                    activity_confidence INTEGER,
                    battery_level REAL,
                    battery_is_charging INTEGER,
                    extras TEXT,
                    json TEXT NOT NULL,
                    locked INTEGER DEFAULT 0
                )
            """)
            _ = db.executeUpdate("CREATE INDEX IF NOT EXISTS locations_timestamp ON locations (timestamp)")
            _ = db.executeUpdate("CREATE INDEX IF NOT EXISTS locations_uuid ON locations (uuid)")
        }
    }

    @objc public func registerConfigChangeHandlers() {
    }

    @objc public func create(_ location: TSLocation, error: UnsafeMutablePointer<NSError?>?) -> Bool {
        guard let json = location.toJson(nil) else { return false }
        let dict = location.toDictionary()
        let coords = dict["coords"] as? [String: Any] ?? [:]
        var result = false

        dbQueue?.inDatabase { db in
            let extras = location.extras.flatMap { try? JSONSerialization.data(withJSONObject: $0) }.flatMap { String(data: $0, encoding: .utf8) }
            result = db.executeUpdate(
                """
                INSERT OR IGNORE INTO locations
                    (uuid, timestamp, latitude, longitude, accuracy, altitude, speed, heading,
                     odometer, is_moving, event, activity_type, battery_level, battery_is_charging, extras, json)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                withArgumentsInArray: [
                    location.uuid,
                    location.timestamp().timeIntervalSince1970,
                    coords["latitude"] ?? 0,
                    coords["longitude"] ?? 0,
                    coords["accuracy"] ?? 0,
                    coords["altitude"] ?? 0,
                    coords["speed"] ?? 0,
                    coords["heading"] ?? 0,
                    location.odometer,
                    location.isMoving ? 1 : 0,
                    location.event,
                    (dict["activity"] as? [String: Any])?["type"] ?? "",
                    (dict["battery"] as? [String: Any])?["level"] ?? 0,
                    (dict["battery"] as? [String: Any])?["is_charging"] ?? false,
                    extras as Any,
                    json
                ]
            )
        }
        return result
    }

    @objc public func all() -> [[String: Any]] {
        return allWithLocking(false)
    }

    @objc public func allWithLocking(_ locking: Bool) -> [[String: Any]] {
        var results: [[String: Any]] = []
        dbQueue?.inDatabase { db in
            let sql = locking ? "SELECT * FROM locations ORDER BY timestamp ASC" : "SELECT * FROM locations WHERE locked = 0 ORDER BY timestamp ASC"
            guard let rs = db.executeQuery(sql) else { return }
            defer { rs.close() }
            while rs.next() {
                if let json = rs.string(forColumn: "json"),
                   let data = json.data(using: .utf8),
                   let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    results.append(dict)
                }
            }
        }
        return results
    }

    @objc public func first() -> [String: Any]? {
        var result: [String: Any]?
        dbQueue?.inDatabase { db in
            guard let rs = db.executeQuery("SELECT * FROM locations WHERE locked = 0 ORDER BY timestamp ASC LIMIT 1") else { return }
            defer { rs.close() }
            if rs.next(), let json = rs.string(forColumn: "json"),
               let data = json.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                result = dict
            }
        }
        return result
    }

    @objc public func getCount() -> Int {
        var count = 0
        dbQueue?.inDatabase { db in
            guard let rs = db.executeQuery("SELECT COUNT(*) FROM locations") else { return }
            defer { rs.close() }
            if rs.next() { count = Int(rs.int(forColumn: 0)) }
        }
        return count
    }

    @objc public func destroy(_ uuid: String) -> Bool {
        var result = false
        dbQueue?.inDatabase { db in
            result = db.executeUpdate("DELETE FROM locations WHERE uuid = ?", withArgumentsInArray: [uuid])
        }
        return result
    }

    @objc public func destroyByUuid(_ uuid: String) -> Bool {
        return destroy(uuid)
    }

    @objc public func destroyAll(_ uuids: [String]) -> Bool {
        var result = false
        dbQueue?.inDatabase { db in
            let placeholders = uuids.map { _ in "?" }.joined(separator: ", ")
            result = db.executeUpdate("DELETE FROM locations WHERE uuid IN (\(placeholders))", withArgumentsInArray: uuids)
        }
        return result
    }

    @objc public func clear() {
        dbQueue?.inDatabase { db in
            _ = db.executeUpdate("DELETE FROM locations")
        }
    }

    @objc public func unlock(_ uuid: String) -> Bool {
        var result = false
        dbQueue?.inDatabase { db in
            result = db.executeUpdate("UPDATE locations SET locked = 0 WHERE uuid = ?", withArgumentsInArray: [uuid])
        }
        return result
    }

    @objc public func unlockAll(_ uuids: [String]) -> Bool {
        var result = false
        dbQueue?.inDatabase { db in
            let placeholders = uuids.map { _ in "?" }.joined(separator: ", ")
            result = db.executeUpdate("UPDATE locations SET locked = 0 WHERE uuid IN (\(placeholders))", withArgumentsInArray: uuids)
        }
        return result
    }

    @objc public func unlock() -> Bool {
        var result = false
        dbQueue?.inDatabase { db in
            result = db.executeUpdate("UPDATE locations SET locked = 0")
        }
        return result
    }

    @objc public func purge(_ query: SQLQuery) -> Bool {
        var result = false
        dbQueue?.inDatabase { db in
            result = db.executeUpdate("DELETE FROM locations", withArgumentsInArray: [])
        }
        return result
    }

    @objc public func shrink(_ count: Int, db: TSDatabase) {
        let current = getCount()
        if current > count {
            let excess = current - count
            _ = db.executeUpdate("DELETE FROM locations WHERE id IN (SELECT id FROM locations ORDER BY timestamp ASC LIMIT ?)", withArgumentsInArray: [excess])
        }
    }

    @objc public func inflate(_ dict: [String: Any]) -> TSLocation {
        let location = TSLocation()
        if let uuid = dict["uuid"] as? String { location.uuid = uuid }
        if let event = dict["event"] as? String { location.event = event }
        if let isMoving = dict["is_moving"] as? Bool { location.isMoving = isMoving }
        if let odometer = dict["odometer"] as? Double { location.odometer = odometer }
        if let extras = dict["extras"] as? [String: Any] { location.extras = extras }
        if let coords = dict["coords"] as? [String: Any] {
            let lat = coords["latitude"] as? Double ?? 0
            let lng = coords["longitude"] as? Double ?? 0
            let accuracy = coords["accuracy"] as? Double ?? 0
            let altitude = coords["altitude"] as? Double ?? 0
            let speed = coords["speed"] as? Double ?? -1
            let heading = coords["heading"] as? Double ?? -1
            var timestamp = Date()
            if let ts = dict["timestamp"] as? String {
                let fmt = ISO8601DateFormatter()
                timestamp = fmt.date(from: ts) ?? Date()
            }
            let coord = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            let loc = CLLocation(coordinate: coord, altitude: altitude, horizontalAccuracy: accuracy, verticalAccuracy: -1, course: heading, speed: speed, timestamp: timestamp)
            location.location = loc
        }
        return location
    }

    @objc public func decodeJSON(_ json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    @objc public func migrate(_ db: TSDatabase) {
    }

    @objc public func hydrate(_ query: SQLQuery) -> [[String: Any]] {
        return all()
    }
}
