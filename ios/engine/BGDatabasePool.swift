import Foundation

@objc public protocol BGDatabasePoolDelegate: NSObjectProtocol {
    @objc optional func databasePool(_ pool: BGDatabasePool, shouldAddDatabaseToPool database: BGDatabase) -> Bool
    @objc optional func databasePool(_ pool: BGDatabasePool, didAddDatabase database: BGDatabase)
}

@objc public class BGDatabasePool: NSObject {

    @objc public var path: String = ""
    @objc public var vfsName: String?
    @objc public var openFlags: Int32 = 0
    @objc public var maximumNumberOfDatabasesToCreate: Int = 5
    @objc public weak var delegate: BGDatabasePoolDelegate?

    private var databaseInPool: [BGDatabase] = []
    private var databaseOutPool: [BGDatabase] = []
    private let lockQueue = DispatchQueue(label: "BGDatabasePool.lock")
    private let semaphore: DispatchSemaphore

    @objc public class func databasePool(withPath path: String) -> BGDatabasePool {
        return BGDatabasePool(path: path)
    }

    @objc public class func databasePool(withPath path: String, flags: Int32) -> BGDatabasePool {
        return BGDatabasePool(path: path, flags: flags)
    }

    @objc public class func databasePool(withURL url: URL) -> BGDatabasePool {
        return BGDatabasePool(url: url)
    }

    @objc public class func databasePool(withURL url: URL, flags: Int32) -> BGDatabasePool {
        return BGDatabasePool(url: url, flags: flags)
    }

    @objc public class func databaseClass() -> AnyClass {
        return BGDatabase.self
    }

    @objc public init(path: String) {
        self.path = path
        self.semaphore = DispatchSemaphore(value: 5)
        super.init()
    }

    @objc public init(path: String, flags: Int32) {
        self.path = path
        self.openFlags = flags
        self.semaphore = DispatchSemaphore(value: 5)
        super.init()
    }

    @objc public init(path: String, flags: Int32, vfs: String?) {
        self.path = path
        self.openFlags = flags
        self.vfsName = vfs
        self.semaphore = DispatchSemaphore(value: 5)
        super.init()
    }

    @objc public init(url: URL) {
        self.path = url.path
        self.semaphore = DispatchSemaphore(value: 5)
        super.init()
    }

    @objc public init(url: URL, flags: Int32) {
        self.path = url.path
        self.openFlags = flags
        self.semaphore = DispatchSemaphore(value: 5)
        super.init()
    }

    @objc public init(url: URL, flags: Int32, vfs: String?) {
        self.path = url.path
        self.openFlags = flags
        self.vfsName = vfs
        self.semaphore = DispatchSemaphore(value: 5)
        super.init()
    }

    @objc public override init() {
        self.semaphore = DispatchSemaphore(value: 5)
        super.init()
    }

    @objc public func countOfCheckedInDatabases() -> Int {
        return executeLocked { self.databaseInPool.count }
    }

    @objc public func countOfCheckedOutDatabases() -> Int {
        return executeLocked { self.databaseOutPool.count }
    }

    @objc public func countOfOpenDatabases() -> Int {
        return executeLocked { self.databaseInPool.count + self.databaseOutPool.count }
    }

    @objc public func releaseAllDatabases() {
        executeLocked {
            self.databaseInPool.removeAll()
            self.databaseOutPool.removeAll()
        }
    }

    func executeLocked<T>(_ block: () -> T) -> T {
        var result: T!
        lockQueue.sync { result = block() }
        return result
    }

    @objc public func executeLocked(_ block: () -> Void) {
        lockQueue.sync(execute: block)
    }

    func db() -> BGDatabase {
        semaphore.wait()
        var db: BGDatabase?
        executeLocked {
            db = self.databaseInPool.popLast()
        }
        if db == nil {
            db = BGDatabase(path: path)
            if openFlags != 0 {
                _ = db?.open(withFlags: openFlags)
            } else {
                _ = db?.open()
            }
        }
        executeLocked {
            if let database = db {
                self.databaseOutPool.append(database)
            }
        }
        return db!
    }

    @objc public func inDatabase(_ block: (BGDatabase) -> Void) {
        let database = db()
        block(database)
        pushDatabaseBackInPool(database)
    }

    @objc public func beginTransaction(_ useDeferred: Bool, withBlock block: (BGDatabase, UnsafeMutablePointer<ObjCBool>) -> Void) {
        inDatabase { db in
            var shouldRollback = ObjCBool(false)
            if useDeferred {
                _ = db.beginDeferredTransaction()
            } else {
                _ = db.beginTransaction()
            }
            block(db, &shouldRollback)
            if shouldRollback.boolValue {
                _ = db.rollback()
            } else {
                _ = db.commit()
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
        inDatabase { db in
            var shouldRollback = ObjCBool(false)
            _ = db.beginImmediateTransaction()
            block(db, &shouldRollback)
            if shouldRollback.boolValue {
                _ = db.rollback()
            } else {
                _ = db.commit()
            }
        }
    }

    @objc public func inExclusiveTransaction(_ block: (BGDatabase, UnsafeMutablePointer<ObjCBool>) -> Void) {
        inDatabase { db in
            var shouldRollback = ObjCBool(false)
            _ = db.beginExclusiveTransaction()
            block(db, &shouldRollback)
            if shouldRollback.boolValue {
                _ = db.rollback()
            } else {
                _ = db.commit()
            }
        }
    }

    @objc public func inSavePoint(_ block: (BGDatabase, UnsafeMutablePointer<ObjCBool>) -> Void) -> Error? {
        inDatabase { db in
            var shouldRollback = ObjCBool(false)
            let name = "sp_\(arc4random())"
            _ = db.startSavePoint(withName: name, error: nil)
            block(db, &shouldRollback)
            if shouldRollback.boolValue {
                _ = db.rollbackToSavePoint(withName: name, error: nil)
            } else {
                _ = db.releaseSavePoint(withName: name, error: nil)
            }
        }
        return nil
    }

    @objc public func pushDatabaseBackInPool(_ database: BGDatabase) {
        executeLocked {
            if let idx = self.databaseOutPool.firstIndex(where: { $0 === database }) {
                self.databaseOutPool.remove(at: idx)
            }
            self.databaseInPool.append(database)
        }
        semaphore.signal()
    }
}
