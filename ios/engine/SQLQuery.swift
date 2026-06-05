import Foundation

@objc public class SQLQuery: NSObject {

    @objc public var start: Double = 0
    @objc public var end: Double = 0
    @objc public var limit: Int = -1
    @objc public var order: Int = 1
    @objc public var arguments: NSMutableArray = NSMutableArray()

    private var _orderString: String = "ASC"

    @objc public override init() {
        super.init()
        self.limit = -1
        self.order = 1
        self.start = 0
        self.end = 0
        self.arguments = NSMutableArray()
    }

    @objc public init(dictionary: [String: Any]) {
        super.init()
        if let s = dictionary["start"] as? Double { self.start = s }
        if let e = dictionary["end"] as? Double { self.end = e }
        if let l = dictionary["limit"] as? Int { self.limit = l }
        if let o = dictionary["order"] as? Int { self.order = o }
    }

    @objc public func addArgument(_ arg: Any) {
        arguments.add(arg)
    }

    @objc public func render() -> String {
        var clauses: [String] = []
        var args: [Any] = []

        if start > 0 {
            clauses.append("timestamp >= ?")
            args.append(start)
        }
        if end > 0 {
            clauses.append("timestamp <= ?")
            args.append(end)
        }

        arguments.addObjects(from: args)

        var sql = clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND ")
        let orderDir = order >= 0 ? "ASC" : "DESC"
        sql += " ORDER BY timestamp \(orderDir)"
        if limit > 0 {
            sql += " LIMIT \(limit)"
        }
        return sql
    }

    @objc public func toString() -> String {
        return render()
    }

    @objc public override var description: String {
        return "<SQLQuery start=\(start) end=\(end) limit=\(limit) order=\(order)>"
    }
}
