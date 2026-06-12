import Foundation

@objc public final class BGDateUtils: NSObject {

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = ISO8601DateFormatter.Options(rawValue: 0xf73)
        formatter.timeZone = TimeZone(abbreviation: "UTC")
        return formatter
    }()

    private static let iso8601ParseFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = ISO8601DateFormatter.Options(rawValue: 0xf73)
        formatter.timeZone = TimeZone(abbreviation: "UTC")
        return formatter
    }()

    @objc public class func iso8601String(from date: Date) -> String {
        return iso8601Formatter.string(from: date)
    }

    @objc public class func date(fromISO8601String string: String) -> Date? {
        return iso8601ParseFormatter.date(from: string)
    }
}
