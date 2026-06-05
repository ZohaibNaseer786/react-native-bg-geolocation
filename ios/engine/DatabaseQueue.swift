import Foundation

@objc public class DatabaseQueue: NSObject {

    private static var _sharedInstance: DatabaseQueue?
    private static let lock = NSLock()

    @objc public var queue: Any?

    @objc public class func sharedInstance() -> DatabaseQueue {
        lock.lock()
        defer { lock.unlock() }
        if _sharedInstance == nil {
            _sharedInstance = DatabaseQueue()
        }
        return _sharedInstance!
    }

    @objc public override init() {
        super.init()
        openDatabase()
    }

    private func databasePath() -> String {
        let docs = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
        return (docs as NSString).appendingPathComponent("TSDatabase.db")
    }

    private func openDatabase() {
        let path = databasePath()
        queue = path
    }

    @objc public func migrateDatabase(_ db: Any?) {
    }

    @objc public func hasMigratedLocations() -> Bool {
        return false
    }

    @objc public func getMigratedLocations() -> [[String: Any]] {
        return []
    }

    @objc public func finishMigration() {
    }
}
