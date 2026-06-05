import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

@objc public class TSStatement: NSObject {

    @objc public var query: String = ""
    @objc public var useCount: Int = 0
    @objc public var inUse: Bool = false
    var statement: OpaquePointer?

    @objc public func reset() {
        if let stmt = statement {
            sqlite3_reset(stmt)
        }
        inUse = false
    }

    @objc public func close() {
        if let stmt = statement {
            sqlite3_finalize(stmt)
            statement = nil
        }
    }

    @objc public override var description: String {
        return "<TSStatement query=\(query) useCount=\(useCount)>"
    }

    deinit {
        close()
    }
}

@objc public class TSDatabase: NSObject {

    @objc public var databasePath: String?
    @objc public var databaseURL: URL?
    @objc public var logsErrors: Bool = true
    @objc public var crashOnErrors: Bool = false
    @objc public var traceExecution: Bool = false
    @objc public var shouldCacheStatements: Bool = false
    @objc public var isOpen: Bool = false
    @objc public var inTransaction: Bool = false
    @objc public var checkedOut: Bool = false
    @objc public var maxBusyRetryTimeInterval: TimeInterval = 2.0
    @objc public var busyRetryTimeout: Int = 0

    var db: OpaquePointer?
    var cachedStatements: [String: TSStatement] = [:]
    var openResultSets: NSMutableSet = NSMutableSet()
    var dateFormat: DateFormatter?

    @objc public class func database(withPath path: String) -> TSDatabase {
        return TSDatabase(path: path)
    }

    @objc public class func database(withURL url: URL) -> TSDatabase {
        return TSDatabase(url: url)
    }

    @objc public class func isSQLiteThreadSafe() -> Bool {
        return sqlite3_threadsafe() != 0
    }

    @objc public class func sqliteLibVersion() -> String {
        return String(cString: sqlite3_libversion())
    }

    @objc public class func TSDBVersion() -> Int32 {
        return sqlite3_libversion_number()
    }

    @objc public class func TSDBUserVersion() -> Int32 {
        return 0
    }

    @objc public class func storeableDate(format: String) -> DateFormatter {
        let fmt = DateFormatter()
        fmt.dateFormat = format
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(abbreviation: "UTC")
        return fmt
    }

    @objc public init(path: String) {
        self.databasePath = path
        self.databaseURL = URL(fileURLWithPath: path)
        super.init()
    }

    @objc public init(url: URL) {
        self.databaseURL = url
        self.databasePath = url.path
        super.init()
    }

    @objc public override init() {
        super.init()
    }

    @objc public func open() -> Bool {
        if isOpen { return true }
        let path = databasePath ?? ":memory:"
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        let rc = sqlite3_open_v2(path, &db, flags, nil)
        if rc == SQLITE_OK {
            isOpen = true
            return true
        }
        return false
    }

    @objc public func open(withFlags flags: Int32) -> Bool {
        if isOpen { return true }
        let path = databasePath ?? ":memory:"
        let rc = sqlite3_open_v2(path, &db, flags, nil)
        if rc == SQLITE_OK {
            isOpen = true
            return true
        }
        return false
    }

    @objc public func open(withFlags flags: Int32, vfs: String?) -> Bool {
        if isOpen { return true }
        let path = databasePath ?? ":memory:"
        let rc = sqlite3_open_v2(path, &db, flags, vfs)
        if rc == SQLITE_OK {
            isOpen = true
            return true
        }
        return false
    }

    @objc public func close() -> Bool {
        clearCachedStatements()
        closeOpenResultSets()
        if db != nil {
            sqlite3_close(db)
            db = nil
        }
        isOpen = false
        return true
    }

    @objc public func goodConnection() -> Bool {
        if !isOpen { return false }
        let rs = executeQuery("SELECT name FROM sqlite_master WHERE type='table'")
        rs?.close()
        return rs != nil
    }

    @objc public func databaseExists() -> Bool {
        guard let path = databasePath else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    @objc public func sqliteHandle() -> OpaquePointer? {
        return db
    }

    @objc public func sqlitePath() -> String {
        return databasePath ?? ""
    }

    @objc public func lastInsertRowId() -> Int64 {
        return sqlite3_last_insert_rowid(db)
    }

    @objc public func changes() -> Int32 {
        return sqlite3_changes(db)
    }

    @objc public func hadError() -> Bool {
        return lastErrorCode() != SQLITE_OK
    }

    @objc public func lastError() -> Error {
        return NSError(domain: "TSDatabase", code: Int(lastErrorCode()), userInfo: [NSLocalizedDescriptionKey: lastErrorMessage()])
    }

    @objc public func lastErrorCode() -> Int32 {
        return sqlite3_errcode(db)
    }

    @objc public func lastExtendedErrorCode() -> Int32 {
        return sqlite3_extended_errcode(db)
    }

    @objc public func lastErrorMessage() -> String {
        return String(cString: sqlite3_errmsg(db))
    }

    @objc public func error(withMessage message: String) -> NSError {
        return NSError(domain: "TSDatabase", code: Int(lastErrorCode()), userInfo: [NSLocalizedDescriptionKey: message])
    }

    @objc public func interrupt() {
        sqlite3_interrupt(db)
    }

    @objc public func warnInUse() {
        if logsErrors {
            print("[TSDatabase] Warning: database in use")
        }
    }

    // MARK: - Statements

    @objc public func cachedStatement(forQuery query: String) -> TSStatement? {
        return cachedStatements[query]
    }

    @objc public func setCachedStatement(_ stmt: TSStatement, forQuery query: String) {
        cachedStatements[query] = stmt
    }

    @objc public func clearCachedStatements() {
        for (_, stmt) in cachedStatements {
            stmt.close()
        }
        cachedStatements.removeAll()
    }

    @objc public func closeOpenResultSets() {
        let sets = openResultSets.copy() as! NSSet
        for obj in sets {
            if let rs = obj as? TSResultSet {
                rs.close()
            }
        }
    }

    @objc public func hasOpenResultSets() -> Bool {
        return openResultSets.count > 0
    }

    @objc public func resultSetDidClose(_ rs: TSResultSet) {
        openResultSets.remove(rs)
    }

    // MARK: - Execute

    @objc public func executeUpdate(_ sql: String) -> Bool {
        return executeUpdate(sql, withArgumentsInArray: [])
    }

    @objc public func executeUpdate(_ sql: String, withArgumentsInArray args: [Any]) -> Bool {
        var stmt: OpaquePointer?
        var rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        if rc != SQLITE_OK {
            if logsErrors { print("[TSDatabase] executeUpdate prepare error: \(lastErrorMessage())") }
            return false
        }
        defer { sqlite3_finalize(stmt) }
        for (i, arg) in args.enumerated() {
            bind(object: arg, toColumn: Int32(i + 1), inStatement: stmt!)
        }
        rc = sqlite3_step(stmt)
        if rc != SQLITE_DONE && rc != SQLITE_ROW {
            if logsErrors { print("[TSDatabase] executeUpdate step error: \(lastErrorMessage())") }
            return false
        }
        return true
    }

    @objc public func executeUpdate(_ sql: String, withParameterDictionary params: [String: Any]) -> Bool {
        return executeUpdate(sql, withArgumentsInArray: Array(params.values))
    }

    public func executeUpdate(_ sql: String, values: [Any], error: UnsafeMutablePointer<NSError?>?) throws -> Bool {
        return executeUpdate(sql, withArgumentsInArray: values)
    }

    public func executeUpdate(withFormat sql: String, _ args: CVarArg...) -> Bool {
        return executeUpdate(String(format: sql, args))
    }

    public func executeUpdate(_ sql: String, error: UnsafeMutablePointer<NSError?>?, withArgumentsInArray args: [Any]?, orDictionary dict: [String: Any]?, orVAList valist: CVaListPointer) -> Bool {
        if let a = args { return executeUpdate(sql, withArgumentsInArray: a) }
        if let d = dict { return executeUpdate(sql, withParameterDictionary: d) }
        return executeUpdate(sql)
    }

    @objc public func update(_ sql: String, withErrorAndBindings bindings: [Any]) -> Bool {
        return executeUpdate(sql, withArgumentsInArray: bindings)
    }

    @objc public func executeUpdate(_ sql: String, withErrorAndBindings bindings: [Any]) -> Bool {
        return executeUpdate(sql, withArgumentsInArray: bindings)
    }

    @objc public func executeStatements(_ sql: String) -> Bool {
        var errMsg: UnsafeMutablePointer<Int8>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errMsg)
        if rc != SQLITE_OK {
            if logsErrors {
                let msg = errMsg.map { String(cString: $0) } ?? "unknown error"
                print("[TSDatabase] executeStatements error: \(msg)")
            }
            sqlite3_free(errMsg)
            return false
        }
        return true
    }

    @objc public func executeStatements(_ sql: String, withResultBlock block: ((NSDictionary) -> Int32)?) -> Bool {
        return executeStatements(sql)
    }

    @objc public func executeQuery(_ sql: String) -> TSResultSet? {
        return executeQuery(sql, withArgumentsInArray: [])
    }

    @objc public func executeQuery(_ sql: String, withArgumentsInArray args: [Any]) -> TSResultSet? {
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        if rc != SQLITE_OK {
            if logsErrors { print("[TSDatabase] executeQuery prepare error: \(lastErrorMessage())") }
            return nil
        }
        for (i, arg) in args.enumerated() {
            bind(object: arg, toColumn: Int32(i + 1), inStatement: stmt!)
        }
        let rs = TSResultSet()
        rs.statement = TSStatement()
        rs.statement?.statement = stmt
        rs.statement?.query = sql
        rs.parentDB = self
        openResultSets.add(rs)
        return rs
    }

    public func executeQuery(_ sql: String, values: [Any], error: UnsafeMutablePointer<NSError?>?) throws -> TSResultSet? {
        return executeQuery(sql, withArgumentsInArray: values)
    }

    @objc public func executeQuery(_ sql: String, withParameterDictionary params: [String: Any]) -> TSResultSet? {
        return executeQuery(sql, withArgumentsInArray: Array(params.values))
    }

    public func executeQuery(_ sql: String, withVAList valist: CVaListPointer) -> TSResultSet? {
        return executeQuery(sql)
    }

    public func executeQuery(withFormat sql: String, _ args: CVarArg...) -> TSResultSet? {
        return executeQuery(String(format: sql, args))
    }

    public func executeQuery(_ sql: String, withArgumentsInArray args: [Any]?, orDictionary dict: [String: Any]?, orVAList valist: CVaListPointer) -> TSResultSet? {
        if let a = args { return executeQuery(sql, withArgumentsInArray: a) }
        if let d = dict { return executeQuery(sql, withParameterDictionary: d) }
        return executeQuery(sql)
    }

    // MARK: - Transactions

    @objc public func beginTransaction() -> Bool {
        let ok = executeUpdate("BEGIN EXCLUSIVE TRANSACTION")
        if ok { inTransaction = true }
        return ok
    }

    @objc public func beginDeferredTransaction() -> Bool {
        let ok = executeUpdate("BEGIN DEFERRED TRANSACTION")
        if ok { inTransaction = true }
        return ok
    }

    @objc public func beginImmediateTransaction() -> Bool {
        let ok = executeUpdate("BEGIN IMMEDIATE TRANSACTION")
        if ok { inTransaction = true }
        return ok
    }

    @objc public func beginExclusiveTransaction() -> Bool {
        let ok = executeUpdate("BEGIN EXCLUSIVE TRANSACTION")
        if ok { inTransaction = true }
        return ok
    }

    @objc public func commit() -> Bool {
        let ok = executeUpdate("COMMIT TRANSACTION")
        if ok { inTransaction = false }
        return ok
    }

    @objc public func rollback() -> Bool {
        let ok = executeUpdate("ROLLBACK TRANSACTION")
        if ok { inTransaction = false }
        return ok
    }

    @objc public func isInTransaction() -> Bool {
        return inTransaction
    }

    @objc public func startSavePoint(withName name: String, error: UnsafeMutablePointer<NSError?>?) -> Bool {
        return executeUpdate("SAVEPOINT \(name)")
    }

    @objc public func releaseSavePoint(withName name: String, error: UnsafeMutablePointer<NSError?>?) -> Bool {
        return executeUpdate("RELEASE SAVEPOINT \(name)")
    }

    @objc public func rollbackToSavePoint(withName name: String, error: UnsafeMutablePointer<NSError?>?) -> Bool {
        return executeUpdate("ROLLBACK TO SAVEPOINT \(name)")
    }

    @objc public func inSavePoint(_ block: (UnsafeMutablePointer<ObjCBool>) -> Void) -> Error? {
        let savepointName = "FMDB_\(arc4random())"
        var shouldRollback = ObjCBool(false)
        _ = startSavePoint(withName: savepointName, error: nil)
        block(&shouldRollback)
        if shouldRollback.boolValue {
            _ = rollbackToSavePoint(withName: savepointName, error: nil)
        } else {
            _ = releaseSavePoint(withName: savepointName, error: nil)
        }
        return nil
    }

    // MARK: - Checkpoint

    @objc public func checkpoint(_ checkpointMode: Int32, error: UnsafeMutablePointer<NSError?>?) -> Bool {
        return sqlite3_wal_checkpoint_v2(db, nil, checkpointMode, nil, nil) == SQLITE_OK
    }

    @objc public func checkpoint(_ checkpointMode: Int32, name: String?, error: UnsafeMutablePointer<NSError?>?) -> Bool {
        return sqlite3_wal_checkpoint_v2(db, name, checkpointMode, nil, nil) == SQLITE_OK
    }

    @objc public func checkpoint(_ checkpointMode: Int32, name: String?, logFrameCount: UnsafeMutablePointer<Int32>?, checkpointCount: UnsafeMutablePointer<Int32>?, error: UnsafeMutablePointer<NSError?>?) -> Bool {
        return sqlite3_wal_checkpoint_v2(db, name, checkpointMode, logFrameCount, checkpointCount) == SQLITE_OK
    }

    // MARK: - Key management

    @objc public func setKey(_ key: String) -> Bool { return true }
    @objc public func setKey(withData keyData: Data) -> Bool { return true }
    @objc public func rekey(_ key: String) -> Bool { return true }
    @objc public func rekey(withData keyData: Data) -> Bool { return true }

    // MARK: - Date helpers

    @objc public func hasDateFormatter() -> Bool {
        return dateFormat != nil
    }

    @objc public func setDateFormat(_ fmt: DateFormatter) {
        dateFormat = fmt
    }

    @objc public func date(fromString dateString: String) -> Date? {
        return dateFormat?.date(from: dateString)
    }

    @objc public func string(fromDate date: Date) -> String {
        return dateFormat?.string(from: date) ?? ""
    }

    // MARK: - Custom functions

    @objc public func makeFunctionNamed(_ name: String, arguments nArgs: Int32, block: @escaping ([AnyObject]) -> AnyObject?) {
    }

    @objc public func makeFunctionNamed(_ name: String, maximumArguments nArgs: Int32, with block: @escaping ([AnyObject]) -> Void) {
    }

    @objc public func resultInt(_ value: Int32, context: OpaquePointer) {
        sqlite3_result_int(context, value)
    }

    @objc public func resultLong(_ value: Int64, context: OpaquePointer) {
        sqlite3_result_int64(context, value)
    }

    @objc public func resultDouble(_ value: Double, context: OpaquePointer) {
        sqlite3_result_double(context, value)
    }

    @objc public func resultString(_ value: String, context: OpaquePointer) {
        sqlite3_result_text(context, value, -1, SQLITE_TRANSIENT)
    }

    @objc public func resultData(_ value: Data, context: OpaquePointer) {
        value.withUnsafeBytes { bytes in
            sqlite3_result_blob(context, bytes.baseAddress, Int32(value.count), SQLITE_TRANSIENT)
        }
    }

    @objc public func resultNull(inContext context: OpaquePointer) {
        sqlite3_result_null(context)
    }

    @objc public func resultError(_ value: String, context: OpaquePointer) {
        sqlite3_result_error(context, value, -1)
    }

    @objc public func resultErrorCode(_ value: Int32, context: OpaquePointer) {
        sqlite3_result_error_code(context, value)
    }

    @objc public func resultErrorNoMemory(inContext context: OpaquePointer) {
        sqlite3_result_error_nomem(context)
    }

    @objc public func resultErrorTooBig(inContext context: OpaquePointer) {
        sqlite3_result_error_toobig(context)
    }

    @objc public func valueString(_ value: OpaquePointer) -> String? {
        return sqlite3_value_text(value).map { String(cString: $0) }
    }

    @objc public func valueData(_ value: OpaquePointer) -> Data? {
        guard let bytes = sqlite3_value_blob(value) else { return nil }
        let len = sqlite3_value_bytes(value)
        return Data(bytes: bytes, count: Int(len))
    }

    @objc public func valueInt(_ value: OpaquePointer) -> Int32 {
        return sqlite3_value_int(value)
    }

    @objc public func valueLong(_ value: OpaquePointer) -> Int64 {
        return sqlite3_value_int64(value)
    }

    @objc public func valueDouble(_ value: OpaquePointer) -> Double {
        return sqlite3_value_double(value)
    }

    @objc public func valueType(_ value: OpaquePointer) -> Int32 {
        return sqlite3_value_type(value)
    }

    // MARK: - Bind helpers

    func bind(object obj: Any, toColumn idx: Int32, inStatement stmt: OpaquePointer) {
        if let num = obj as? NSNumber {
            let type = String(cString: num.objCType)
            if type == "d" || type == "f" {
                sqlite3_bind_double(stmt, idx, num.doubleValue)
            } else if type == "q" || type == "Q" {
                sqlite3_bind_int64(stmt, idx, num.int64Value)
            } else {
                sqlite3_bind_int(stmt, idx, num.int32Value)
            }
        } else if let str = obj as? String {
            sqlite3_bind_text(stmt, idx, str, -1, SQLITE_TRANSIENT)
        } else if let data = obj as? Data {
            data.withUnsafeBytes { bytes in
                sqlite3_bind_blob(stmt, idx, bytes.baseAddress, Int32(data.count), SQLITE_TRANSIENT)
            }
        } else if let date = obj as? Date {
            let str = String(date.timeIntervalSince1970)
            sqlite3_bind_text(stmt, idx, str, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, idx)
        }
    }

    public func extractSQL(_ sql: String, argumentsList args: CVaListPointer, into outSQL: UnsafeMutablePointer<NSString?>, arguments: NSMutableArray) -> Bool {
        return true
    }
}

// MARK: - TSDatabaseAdditions

extension TSDatabase {

    public func string(forQuery query: String, _ args: Any...) -> String? {
        guard let rs = executeQuery(query, withArgumentsInArray: args), rs.next() else { return nil }
        defer { rs.close() }
        return rs.string(forColumn: 0)
    }

    public func int(forQuery query: String, _ args: Any...) -> Int32 {
        guard let rs = executeQuery(query, withArgumentsInArray: args), rs.next() else { return 0 }
        defer { rs.close() }
        return rs.int(forColumn: 0)
    }

    public func long(forQuery query: String, _ args: Any...) -> Int64 {
        guard let rs = executeQuery(query, withArgumentsInArray: args), rs.next() else { return 0 }
        defer { rs.close() }
        return rs.long(forColumn: 0)
    }

    public func bool(forQuery query: String, _ args: Any...) -> Bool {
        guard let rs = executeQuery(query, withArgumentsInArray: args), rs.next() else { return false }
        defer { rs.close() }
        return rs.bool(forColumn: 0)
    }

    public func double(forQuery query: String, _ args: Any...) -> Double {
        guard let rs = executeQuery(query, withArgumentsInArray: args), rs.next() else { return 0 }
        defer { rs.close() }
        return rs.double(forColumn: 0)
    }

    public func data(forQuery query: String, _ args: Any...) -> Data? {
        guard let rs = executeQuery(query, withArgumentsInArray: args), rs.next() else { return nil }
        defer { rs.close() }
        return rs.data(forColumn: 0)
    }

    public func date(forQuery query: String, _ args: Any...) -> Date? {
        guard let rs = executeQuery(query, withArgumentsInArray: args), rs.next() else { return nil }
        defer { rs.close() }
        return rs.date(forColumn: 0)
    }

    @objc public func tableExists(_ tableName: String) -> Bool {
        guard let rs = executeQuery("SELECT [sql] FROM (SELECT [sql] FROM sqlite_master UNION ALL SELECT [sql] FROM sqlite_temp_master) WHERE type != 'meta' AND name LIKE ?", withArgumentsInArray: [tableName]), rs.next() else { return false }
        rs.close()
        return true
    }

    @objc public func columnExists(_ column: String, inTableWithName table: String) -> Bool {
        var exists = false
        if let rs = executeQuery("PRAGMA table_info('\(table)')") {
            while rs.next() {
                if let name = rs.string(forColumn: "name"), name.lowercased() == column.lowercased() {
                    exists = true
                    break
                }
            }
            rs.close()
        }
        return exists
    }

    @objc public func columnExists(_ column: String, columnName: String) -> Bool {
        return columnExists(column, inTableWithName: columnName)
    }

    @objc public func getSchema() -> TSResultSet? {
        return executeQuery("SELECT type, name, tbl_name, rootpage, sql FROM (SELECT * FROM sqlite_master UNION ALL SELECT * FROM sqlite_temp_master) WHERE type != 'meta' AND name NOT LIKE 'sqlite_%' ORDER BY tbl_name, type DESC, name")
    }

    @objc public func getTableSchema(_ tableName: String) -> TSResultSet? {
        return executeQuery("PRAGMA table_info('\(tableName)')")
    }

    @objc public func userVersion() -> UInt32 {
        guard let rs = executeQuery("PRAGMA user_version"), rs.next() else { return 0 }
        let v = UInt32(bitPattern: rs.int(forColumn: 0))
        rs.close()
        return v
    }

    @objc public func setUserVersion(_ version: UInt32) {
        _ = executeUpdate("PRAGMA user_version = \(version)")
    }

    @objc public func applicationID() -> UInt32 {
        guard let rs = executeQuery("PRAGMA application_id"), rs.next() else { return 0 }
        let v = UInt32(bitPattern: rs.int(forColumn: 0))
        rs.close()
        return v
    }

    @objc public func setApplicationID(_ appID: UInt32) {
        _ = executeUpdate("PRAGMA application_id = \(appID)")
    }

    @objc public func validateSQL(_ sql: String, error: UnsafeMutablePointer<NSError?>?) -> Bool {
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        if stmt != nil { sqlite3_finalize(stmt) }
        return rc == SQLITE_OK
    }
}
