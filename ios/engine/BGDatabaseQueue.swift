import Foundation

@objc public class BGDatabaseQueue: NSObject {

    @objc public var path: String = ""
    @objc public var vfsName: String?
    @objc public var openFlags: Int32 = 0

    private var db: BGDatabase?
    private let queue: DispatchQueue
    private static let kQueueKey = DispatchSpecificKey<BGDatabaseQueue>()

    @objc public class func databaseQueue(withPath path: String) -> BGDatabaseQueue {
        return BGDatabaseQueue(path: path)
    }

    @objc public class func databaseQueue(withPath path: String, flags: Int32) -> BGDatabaseQueue {
        return BGDatabaseQueue(path: path, flags: flags)
    }

    @objc public class func databaseQueue(withURL url: URL) -> BGDatabaseQueue {
        return BGDatabaseQueue(url: url)
    }

    @objc public class func databaseQueue(withURL url: URL, flags: Int32) -> BGDatabaseQueue {
        return BGDatabaseQueue(url: url, flags: flags)
    }

    @objc public class func databaseClass() -> AnyClass {
        return BGDatabase.self
    }

    @objc public init(path: String) {
        self.path = path
        self.queue = DispatchQueue(label: "BGDatabaseQueue.\(path)")
        super.init()
        openDatabase()
    }

    @objc public init(path: String, flags: Int32) {
        self.path = path
        self.openFlags = flags
        self.queue = DispatchQueue(label: "BGDatabaseQueue.\(path)")
        super.init()
        openDatabase()
    }

    @objc public init(path: String, flags: Int32, vfs: String?) {
        self.path = path
        self.openFlags = flags
        self.vfsName = vfs
        self.queue = DispatchQueue(label: "BGDatabaseQueue.\(path)")
        super.init()
        openDatabase()
    }

    @objc public init(url: URL) {
        self.path = url.path
        self.queue = DispatchQueue(label: "BGDatabaseQueue.\(url.path)")
        super.init()
        openDatabase()
    }

    @objc public init(url: URL, flags: Int32) {
        self.path = url.path
        self.openFlags = flags
        self.queue = DispatchQueue(label: "BGDatabaseQueue.\(url.path)")
        super.init()
        openDatabase()
    }

    @objc public init(url: URL, flags: Int32, vfs: String?) {
        self.path = url.path
        self.openFlags = flags
        self.vfsName = vfs
        self.queue = DispatchQueue(label: "BGDatabaseQueue.\(url.path)")
        super.init()
        openDatabase()
    }

    @objc public override init() {
        self.queue = DispatchQueue(label: "BGDatabaseQueue.default")
        super.init()
    }

    private func openDatabase() {
        let database = BGDatabase(path: path)
        if openFlags != 0 {
            _ = database.open(withFlags: openFlags)
        } else {
            _ = database.open()
        }
        db = database
        queue.setSpecific(key: BGDatabaseQueue.kQueueKey, value: self)
    }

    @objc public func database() -> BGDatabase? {
        return db
    }

    @objc public func close() {
        queue.sync {
            self.db?.close()
            self.db = nil
        }
    }

    @objc public func interrupt() {
        db?.interrupt()
    }

    @objc public func inDatabase(_ block: (BGDatabase) -> Void) {
        queue.sync {
            guard let database = self.db else { return }
            block(database)
            if database.hasOpenResultSets() {
                database.closeOpenResultSets()
            }
        }
    }

    @objc public func beginTransaction(_ useDeferred: Bool, withBlock block: (BGDatabase, UnsafeMutablePointer<ObjCBool>) -> Void) {
        queue.sync {
            guard let database = self.db else { return }
            var shouldRollback = ObjCBool(false)
            if useDeferred {
                _ = database.beginDeferredTransaction()
            } else {
                _ = database.beginTransaction()
            }
            block(database, &shouldRollback)
            if shouldRollback.boolValue {
                _ = database.rollback()
            } else {
                _ = database.commit()
            }
        }
    }

    @objc public func inTransaction(_ block: (BGDatabase, UnsafeMutablePointer<ObjCBool>) -> Void) {
        beginTransaction(false, withBlock: block)
    }

    @objc public func inDeferredTransaction(_ block: (BGDatabase, UnsafeMutablePointer<ObjCBool>) -> Void) {
        beginTransaction(true, withBlock: block)
    }

    @objc public func inImmediateTransaction(_ block: (BGDatabase, UnsafeMutablePointer<ObjCBool>) -> Void) {
        queue.sync {
            guard let database = self.db else { return }
            var shouldRollback = ObjCBool(false)
            _ = database.beginImmediateTransaction()
            block(database, &shouldRollback)
            if shouldRollback.boolValue {
                _ = database.rollback()
            } else {
                _ = database.commit()
            }
        }
    }

    @objc public func inExclusiveTransaction(_ block: (BGDatabase, UnsafeMutablePointer<ObjCBool>) -> Void) {
        queue.sync {
            guard let database = self.db else { return }
            var shouldRollback = ObjCBool(false)
            _ = database.beginExclusiveTransaction()
            block(database, &shouldRollback)
            if shouldRollback.boolValue {
                _ = database.rollback()
            } else {
                _ = database.commit()
            }
        }
    }

    @objc public func inSavePoint(_ block: (BGDatabase, UnsafeMutablePointer<ObjCBool>) -> Void) -> Error? {
        queue.sync {
            guard let database = self.db else { return }
            var shouldRollback = ObjCBool(false)
            let name = "sp_\(arc4random())"
            _ = database.startSavePoint(withName: name, error: nil)
            block(database, &shouldRollback)
            if shouldRollback.boolValue {
                _ = database.rollbackToSavePoint(withName: name, error: nil)
            } else {
                _ = database.releaseSavePoint(withName: name, error: nil)
            }
        }
        return nil
    }

    @objc public func checkpoint(_ checkpointMode: Int32, error: UnsafeMutablePointer<NSError?>?) -> Bool {
        var result = false
        queue.sync {
            result = self.db?.checkpoint(checkpointMode, error: error) ?? false
        }
        return result
    }

    @objc public func checkpoint(_ checkpointMode: Int32, name: String?, error: UnsafeMutablePointer<NSError?>?) -> Bool {
        var result = false
        queue.sync {
            result = self.db?.checkpoint(checkpointMode, name: name, error: error) ?? false
        }
        return result
    }

    @objc public func checkpoint(_ checkpointMode: Int32, name: String?, logFrameCount: UnsafeMutablePointer<Int32>?, checkpointCount: UnsafeMutablePointer<Int32>?, error: UnsafeMutablePointer<NSError?>?) -> Bool {
        var result = false
        queue.sync {
            result = self.db?.checkpoint(checkpointMode, name: name, logFrameCount: logFrameCount, checkpointCount: checkpointCount, error: error) ?? false
        }
        return result
    }
}
