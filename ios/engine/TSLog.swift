import Foundation
import MessageUI
import CoreLocation

@objc public class TSLog: NSObject {

    private static var _sharedInstance: TSLog?
    private static let lock = NSLock()

    @objc public var logLevel: Int = 5
    @objc public var maxAge: Int = 3
    @objc public var deviceInfo: [String: Any] = [:]
    @objc public var pendingEmailSuccess: (() -> Void)?

    @objc public var locationCompleteListener: AnyObject?
    @objc public var locationErrorListener: AnyObject?
    @objc public var locationSampleListener: AnyObject?
    @objc public var locationTrackingListener: AnyObject?
    @objc public var heartbeatListener: AnyObject?
    @objc public var motionChangeCompleteListener: AnyObject?
    @objc public var motionChangeSampleListener: AnyObject?
    @objc public var motionChangeErrorListener: AnyObject?
    @objc public var geofenceCompleteListener: AnyObject?
    @objc public var watchPositionCompleteListener: AnyObject?

    private let logQueue = DispatchQueue(label: "TSLog.queue", attributes: .concurrent)
    private var logEntries: [String] = []
    private var dbQueue: TSDatabaseQueue?

    @objc public class func sharedInstance() -> TSLog {
        lock.lock()
        defer { lock.unlock() }
        if _sharedInstance == nil {
            _sharedInstance = TSLog()
        }
        return _sharedInstance!
    }

    @objc public override init() {
        super.init()
    }

    @objc public func configure() {
        setupDatabase()
        subscribeEventBus()
    }

    private func setupDatabase() {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        guard let docPath = paths.first else { return }
        let dbPath = docPath.appendingPathComponent("TSLog.db")
        dbQueue = TSDatabaseQueue(path: dbPath.path)
        dbQueue?.inDatabase { db in
            _ = db.executeUpdate("""
                CREATE TABLE IF NOT EXISTS logs (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp REAL NOT NULL,
                    level INTEGER NOT NULL,
                    tag TEXT,
                    message TEXT NOT NULL
                )
            """)
            _ = db.executeUpdate("CREATE INDEX IF NOT EXISTS logs_timestamp ON logs (timestamp)")
        }
    }

    @objc public func subscribeEventBus() {
        let bus = TSEventBus.sharedInstance()
        locationCompleteListener = bus.on(TSEventNames.locationComplete) { [weak self] _ in
            self?.onLocationComplete()
        } as AnyObject
        locationErrorListener = bus.on(TSEventNames.locationError) { [weak self] _ in
            self?.onLocationError()
        } as AnyObject
        locationSampleListener = bus.on(TSEventNames.locationSample) { [weak self] _ in
            self?.onLocationSample()
        } as AnyObject
        heartbeatListener = bus.on(TSEventNames.heartbeat) { [weak self] payload in
            self?.onHeartbeat(payload as? [String: Any])
        } as AnyObject
        geofenceCompleteListener = bus.on(TSEventNames.geofenceComplete) { [weak self] payload in
            self?.onGeofence(payload as? [String: Any])
        } as AnyObject
        motionChangeCompleteListener = bus.on(TSEventNames.motionChangeComplete) { [weak self] payload in
            self?.onMotionChangeComplete(payload as? [String: Any])
        } as AnyObject
    }

    @objc public func unsubscribeEventBus() {
        let bus = TSEventBus.sharedInstance()
        if let token = locationCompleteListener as? String { bus.off(TSEventNames.locationComplete, token: token) }
        if let token = locationErrorListener as? String { bus.off(TSEventNames.locationError, token: token) }
        if let token = locationSampleListener as? String { bus.off(TSEventNames.locationSample, token: token) }
        if let token = heartbeatListener as? String { bus.off(TSEventNames.heartbeat, token: token) }
        if let token = geofenceCompleteListener as? String { bus.off(TSEventNames.geofenceComplete, token: token) }
        if let token = motionChangeCompleteListener as? String { bus.off(TSEventNames.motionChangeComplete, token: token) }
    }

    public func setLogLevel(_ level: Int) {
        self.logLevel = level
    }

    public func setMaxAge(_ days: Int) {
        self.maxAge = days
        purgeOldEntries()
    }

    @objc public func notify(_ message: String, debug: Bool) {
        let level = debug ? 5 : 3
        guard level <= logLevel else { return }
        let entry = "[TSLocationManager \(timestamp())] \(message)"
        logQueue.async(flags: .barrier) {
            self.logEntries.append(entry)
            self.writeToDatabase(level: level, tag: "TSLocationManager", message: message)
        }
    }

    @objc public func alert(_ tag: String, message: String) {
        guard 2 <= logLevel else { return }
        let entry = "[\(timestamp())] [\(tag)] \(message)"
        logQueue.async(flags: .barrier) {
            self.logEntries.append(entry)
            self.writeToDatabase(level: 2, tag: tag, message: message)
        }
    }

    @objc public func commit() {
        logQueue.sync(flags: .barrier) {
            self.logEntries.removeAll()
        }
    }

    @objc public func destroy() {
        logQueue.async(flags: .barrier) {
            self.logEntries.removeAll()
        }
        dbQueue?.inDatabase { db in
            _ = db.executeUpdate("DELETE FROM logs")
        }
    }

    @objc public func getLog(_ query: LogQuery) -> [[String: Any]] {
        var results: [[String: Any]] = []
        dbQueue?.inDatabase { db in
            let sql = buildQuery(query)
            guard let rs = db.executeQuery(sql, withArgumentsInArray: query.arguments as! [Any]) else { return }
            defer { rs.close() }
            while rs.next() {
                var entry: [String: Any] = [:]
                if let ts = rs.string(forColumn: "timestamp") { entry["timestamp"] = ts }
                if let level = rs.string(forColumn: "level") { entry["level"] = level }
                if let tag = rs.string(forColumn: "tag") { entry["tag"] = tag }
                if let msg = rs.string(forColumn: "message") { entry["message"] = msg }
                results.append(entry)
            }
        }
        return results
    }

    @objc public func emailLog(_ to: String, query: LogQuery, success: (() -> Void)?, failure: ((Error) -> Void)?) {
        guard MFMailComposeViewController.canSendMail() else {
            failure?(NSError(domain: "TSLog", code: -1, userInfo: [NSLocalizedDescriptionKey: "Mail not available"]))
            return
        }
        let entries = getLog(query)
        let body = entries.map { entry -> String in
            let ts = entry["timestamp"] as? String ?? ""
            let tag = entry["tag"] as? String ?? ""
            let msg = entry["message"] as? String ?? ""
            return "[\(ts)] [\(tag)] \(msg)"
        }.joined(separator: "\n")

        DispatchQueue.main.async {
            let vc = MFMailComposeViewController()
            vc.mailComposeDelegate = self
            vc.setToRecipients([to])
            vc.setSubject("TSLocationManager Log")
            vc.setMessageBody(body, isHTML: false)
            self.pendingEmailSuccess = success
            // Present from top-most view controller
            if let rootVC = UIApplication.shared.windows.first?.rootViewController {
                var topVC = rootVC
                while let presented = topVC.presentedViewController { topVC = presented }
                topVC.present(vc, animated: true)
            }
        }
    }

    @objc public func uploadLog(_ url: String, query: LogQuery, success: (([String: Any]) -> Void)?, failure: ((Error) -> Void)?) {
        let entries = getLog(query)
        guard let requestURL = URL(string: url) else {
            failure?(NSError(domain: "TSLog", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]))
            return
        }
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["logs": entries, "deviceInfo": deviceInfo]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                failure?(error)
                return
            }
            if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                success?(json)
            } else {
                success?([:])
            }
        }.resume()
    }

    @objc public func gzip(_ data: Data) -> Data? {
        return data
    }

    @objc public func playSound(_ soundId: SystemSoundID) {
        AudioServicesPlaySystemSound(soundId)
    }

    @objc public func playSound(_ soundId: SystemSoundID, debug: Bool) {
        guard debug else { return }
        playSound(soundId)
    }

    // MARK: - Event handlers

    @objc public func onLocationComplete() {
        notify("Location complete", debug: true)
    }

    @objc public func onLocationError() {
        notify("Location error", debug: false)
    }

    @objc public func onLocationSample() {
        notify("Location sample", debug: true)
    }

    @objc public func onHeartbeat(_ payload: [String: Any]?) {
        notify("Heartbeat", debug: true)
    }

    @objc public func onGeofence(_ payload: [String: Any]?) {
        notify("Geofence event", debug: true)
    }

    @objc public func onMotionChangeComplete(_ payload: [String: Any]?) {
        notify("Motion change complete", debug: true)
    }

    @objc public func onChangeDebug(_ debug: Bool) {
    }

    @objc public func onChangeLogLevel(_ level: Int) {
        logLevel = level
    }

    @objc public func onChangeLogMaxDays(_ days: Int) {
        maxAge = days
        purgeOldEntries()
    }


    // MARK: - Logging interface

    @objc public func shouldLog(_ level: Int) -> Bool {
        return level <= logLevel
    }

    @objc public func log(_ level: Int, tag: Int, function: String, message: String) {
        guard shouldLog(level) else { return }
        let tagName = "tag:\(tag)"
        let entry = "[\(timestamp())] [\(tagName)] [\(function)] \(message)"
        logQueue.async(flags: .barrier) {
            self.logEntries.append(entry)
            self.writeToDatabase(level: level, tag: tagName, message: "\(function): \(message)")
        }
    }

    // MARK: - Private helpers

    private func timestamp() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return fmt.string(from: Date())
    }

    private func writeToDatabase(level: Int, tag: String, message: String) {
        dbQueue?.inDatabase { db in
            _ = db.executeUpdate(
                "INSERT INTO logs (timestamp, level, tag, message) VALUES (?, ?, ?, ?)",
                withArgumentsInArray: [Date().timeIntervalSince1970, level, tag, message]
            )
        }
    }

    private func purgeOldEntries() {
        let cutoff = Date().timeIntervalSince1970 - Double(maxAge) * 86400
        dbQueue?.inDatabase { db in
            _ = db.executeUpdate("DELETE FROM logs WHERE timestamp < ?", withArgumentsInArray: [cutoff])
        }
    }

    private func buildQuery(_ query: LogQuery) -> String {
        var conditions: [String] = []
        if query.start > 0 {
            conditions.append("timestamp >= \(query.start)")
        }
        if query.end > 0 {
            conditions.append("timestamp <= \(query.end)")
        }
        var sql = "SELECT * FROM logs"
        if !conditions.isEmpty {
            sql += " WHERE " + conditions.joined(separator: " AND ")
        }
        sql += " ORDER BY timestamp \(query.order == 0 ? "DESC" : "ASC")"
        if query.limit > 0 {
            sql += " LIMIT \(query.limit)"
        }
        return sql
    }
}

import AudioToolbox
import UIKit

extension TSLog: MFMailComposeViewControllerDelegate {
    public func mailComposeController(_ controller: MFMailComposeViewController,
                                      didFinishWith result: MFMailComposeResult,
                                      error: Error?) {
        controller.dismiss(animated: true) {
            if result == .sent { self.pendingEmailSuccess?() }
            self.pendingEmailSuccess = nil
        }
    }
}
