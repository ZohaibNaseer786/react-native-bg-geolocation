import Foundation

@objc public class TSResultSet: NSObject {

    private var rows: [[String: Any]] = []
    private var index: Int = -1
    private var columnNames: [String] = []

    // Properties used by TSDatabase for sqlite statement management
    @objc public var statement: TSStatement?
    @objc public weak var parentDB: AnyObject?

    @objc public init(rows: [[String: Any]]) {
        self.rows = rows
        super.init()
    }

    @objc public override init() {
        super.init()
    }

    @objc public func next() -> Bool {
        index += 1
        return index < rows.count
    }

    @objc public func close() {
        index = -1
    }

    @objc public func hasAnotherRow() -> Bool {
        return (index + 1) < rows.count
    }

    @objc public func count() -> Int {
        return rows.count
    }

    @objc public func string(forColumn column: String) -> String? {
        guard index >= 0 && index < rows.count else { return nil }
        return rows[index][column] as? String
    }

    @objc public func int(forColumn column: String) -> Int32 {
        guard index >= 0 && index < rows.count else { return 0 }
        return rows[index][column] as? Int32 ?? 0
    }

    @objc public func long(forColumn column: String) -> Int64 {
        guard index >= 0 && index < rows.count else { return 0 }
        return rows[index][column] as? Int64 ?? 0
    }

    @objc public func double(forColumn column: String) -> Double {
        guard index >= 0 && index < rows.count else { return 0 }
        return rows[index][column] as? Double ?? 0
    }

    @objc public func bool(forColumn column: String) -> Bool {
        guard index >= 0 && index < rows.count else { return false }
        return rows[index][column] as? Bool ?? false
    }

    @objc public func data(forColumn column: String) -> Data? {
        guard index >= 0 && index < rows.count else { return nil }
        return rows[index][column] as? Data
    }

    @objc public func date(forColumn column: String) -> Date? {
        guard index >= 0 && index < rows.count else { return nil }
        if let d = rows[index][column] as? Date { return d }
        if let ti = rows[index][column] as? Double { return Date(timeIntervalSince1970: ti) }
        return nil
    }

    @objc public func object(forColumn column: String) -> Any? {
        guard index >= 0 && index < rows.count else { return nil }
        return rows[index][column]
    }

    @objc public func resultDictionary() -> [String: Any]? {
        guard index >= 0 && index < rows.count else { return nil }
        return rows[index]
    }

    // MARK: - Integer column index variants

    private func columnName(at idx: Int) -> String? {
        guard idx >= 0 && idx < columnNames.count else { return nil }
        return columnNames[idx]
    }

    public func string(forColumn idx: Int) -> String? {
        guard index >= 0 && index < rows.count else { return nil }
        let row = rows[index]
        let col = columnName(at: idx) ?? row.keys.sorted()[safe: idx]
        guard let col = col else { return nil }
        return row[col] as? String
    }

    public func int(forColumn idx: Int) -> Int32 {
        guard index >= 0 && index < rows.count else { return 0 }
        let row = rows[index]
        let col = columnName(at: idx) ?? row.keys.sorted()[safe: idx]
        guard let col = col else { return 0 }
        return row[col] as? Int32 ?? Int32(row[col] as? Int ?? 0)
    }

    public func long(forColumn idx: Int) -> Int64 {
        guard index >= 0 && index < rows.count else { return 0 }
        let row = rows[index]
        let col = columnName(at: idx) ?? row.keys.sorted()[safe: idx]
        guard let col = col else { return 0 }
        return row[col] as? Int64 ?? Int64(row[col] as? Int ?? 0)
    }

    public func double(forColumn idx: Int) -> Double {
        guard index >= 0 && index < rows.count else { return 0 }
        let row = rows[index]
        let col = columnName(at: idx) ?? row.keys.sorted()[safe: idx]
        guard let col = col else { return 0 }
        return row[col] as? Double ?? 0
    }

    public func bool(forColumn idx: Int) -> Bool {
        guard index >= 0 && index < rows.count else { return false }
        let row = rows[index]
        let col = columnName(at: idx) ?? row.keys.sorted()[safe: idx]
        guard let col = col else { return false }
        return row[col] as? Bool ?? false
    }

    public func data(forColumn idx: Int) -> Data? {
        guard index >= 0 && index < rows.count else { return nil }
        let row = rows[index]
        let col = columnName(at: idx) ?? row.keys.sorted()[safe: idx]
        guard let col = col else { return nil }
        return row[col] as? Data
    }

    public func date(forColumn idx: Int) -> Date? {
        guard index >= 0 && index < rows.count else { return nil }
        let row = rows[index]
        let col = columnName(at: idx) ?? row.keys.sorted()[safe: idx]
        guard let col = col else { return nil }
        if let d = row[col] as? Date { return d }
        if let ti = row[col] as? Double { return Date(timeIntervalSince1970: ti) }
        return nil
    }
}

private extension Array {
    subscript(safe idx: Int) -> Element? {
        guard idx >= 0 && idx < count else { return nil }
        return self[idx]
    }
}
