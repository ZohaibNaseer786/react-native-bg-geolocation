import Foundation
import UIKit

@objc public class BGHttpSyncMetrics: NSObject {

    @objc public var flushId: String = UUID().uuidString
    @objc public var lockedRecords: [[String: Any]] = []
    @objc public var lockedRecordsIsBatch: Bool = false
    @objc public var currentBatchUuids: [String] = []
    @objc public var queuedBefore: Int = 0
    @objc public var pages: Int = 0
    @objc public var synced: Int = 0
    @objc public var retryCount: Int = 0
    @objc public var authRefreshAttempted: Bool = false
    @objc public var watchdogArmed: Bool = false
    @objc public var t0: Date = Date()

    @objc public override init() {
        super.init()
    }
}

@objc public class BGHttpService: NSObject {

    private static var _sharedInstance: BGHttpService?
    private static let instanceLock = NSLock()

    @objc public class func sharedInstance() -> BGHttpService {
        instanceLock.lock()
        defer { instanceLock.unlock() }
        if _sharedInstance == nil { _sharedInstance = BGHttpService() }
        return _sharedInstance!
    }

    // MARK: - State

    @objc public var isBusy: Bool = false
    @objc public var hasNetworkConnection: Bool = true
    @objc public var overrideSyncThreshold: Bool = false
    @objc public var autoSyncThreshold: Int = 0
    @objc public var auth: BGAuthorization?
    @objc public var reachability: BGReachability?
    @objc public var metrics: BGHttpSyncMetrics?
    @objc public var bgTask: UIBackgroundTaskIdentifier = .invalid
    @objc public var callback: (() -> Void)?
    @objc public var syncedRecords: [String] = []

    private let flushQueue = DispatchQueue(label: "BGHttpService.flush")
    private var watchdogTimer: Timer?
    private var isMonitoring: Bool = false

    @objc public override init() {
        super.init()
    }

    @objc public func startMonitoring() {
        guard !isMonitoring else {
            resumePendingAutoSync()
            return
        }
        isMonitoring = true
        reachability = BGReachability.reachability(forHostName: "google.com")
        reachability?.startMonitoring { [weak self] isReachable in
            self?.onConnectivityChange(isReachable)
        }
        registerConfigChangeHandlers()
        resumePendingAutoSync()
    }

    @objc public func stopMonitoring() {
        reachability?.stopMonitoring()
        reachability = nil
        isMonitoring = false
    }

    @objc public func registerConfigChangeHandlers() {
    }

    @objc public func onChangeAutoSync() {
    }

    // MARK: - Flush

    @objc public func flush() {
        flush(nil, failure: nil)
    }

    @objc public func flush(_ success: (([String: Any]) -> Void)?) {
        flush(success, failure: nil)
    }

    @objc public func flush(_ success: (([String: Any]) -> Void)?, failure: ((Error) -> Void)?) {
        beginFlush(withCallback: success, overrideSyncThreshold: false, error: nil)
    }

    /// Flush persisted locations during a brief Core Location background wake.
    ///
    /// The record is already durable in SQLite before this is called. Reserving
    /// background execution here, before hopping onto flushQueue, gives the
    /// request the best chance to finish when iOS has relaunched or resumed the
    /// app for a location event. If the request cannot finish, the record stays
    /// queued and resumePendingAutoSync retries it on the next native startup.
    @objc public func flushForBackgroundWake() {
        beginBackgroundFlushTask()
        beginFlush(withCallback: nil, overrideSyncThreshold: true, error: nil)
    }

    @objc public func resumePendingAutoSync() {
        let http = BGConfig.sharedInstance().http
        guard http.autoSync, http.hasValidUrl else { return }
        if BGAppState.sharedInstance().isInBackground ||
            BGAppState.sharedInstance().didLaunchInBackground {
            flushForBackgroundWake()
        } else {
            flush()
        }
    }

    @objc public func beginFlush(withCallback callback: (([String: Any]) -> Void)?, overrideSyncThreshold override: Bool, error: UnsafeMutablePointer<NSError?>?) {
        flushQueue.async { [weak self] in
            guard let self = self else { return }
            guard !self.isBusy else { return }
            guard self.hasNetworkConnection else {
                self.endBackgroundFlushTask()
                return
            }

            let dao = BGLocationDAO.sharedInstance()
            let records = dao.allWithLocking(true)
            guard !records.isEmpty else {
                callback?([:])
                self.endBackgroundFlushTask()
                return
            }

            self.autoSyncThreshold = BGConfig.sharedInstance().http.autoSyncThreshold
            let threshold = self.autoSyncThreshold
            guard override || records.count >= threshold || threshold == 0 else {
                self.endBackgroundFlushTask()
                return
            }

            self.isBusy = true
            let m = BGHttpSyncMetrics()
            m.lockedRecords = records
            m.queuedBefore = records.count
            self.metrics = m

            self.armFlushWatchdog()
            self.continueFlush()
        }
    }

    @objc public func continueFlush() {
        guard let m = metrics else { resetFlushStateLocked(); return }

        let config = BGConfig.sharedInstance()
        let httpConfig = config.http

        if httpConfig.batchSync {
            scheduleBatchPost()
        } else {
            schedulePost()
        }
    }

    @objc public func schedulePost() {
        guard let m = metrics, !m.lockedRecords.isEmpty else {
            finish([:], error: nil)
            return
        }
        let record = m.lockedRecords[m.pages]
        post(record)
    }

    @objc public func scheduleBatchPost() {
        guard let m = metrics else { return }
        let config = BGConfig.sharedInstance().http
        let maxBatch = config.effectiveBatchSize
        let slice = maxBatch > 0 ? Array(m.lockedRecords.prefix(maxBatch)) : m.lockedRecords
        m.lockedRecordsIsBatch = true
        m.currentBatchUuids = slice.compactMap { $0["uuid"] as? String }
        postBatch(slice)
    }

    @objc public func post(_ record: [String: Any]) {
        let config = BGConfig.sharedInstance()
        let httpConfig = config.http
        guard httpConfig.hasValidUrl else {
            finish([:], error: nil)
            return
        }

        let request = buildRequest(for: record, config: httpConfig)
        doPost(request) { [weak self] response in
            self?.parseResponse(response)
        }
    }

    @objc public func postBatch(_ records: [[String: Any]]) {
        let config = BGConfig.sharedInstance()
        let httpConfig = config.http
        guard httpConfig.hasValidUrl else {
            finish([:], error: nil)
            return
        }

        var body: [String: Any] = [:]
        let root = httpConfig.rootProperty
        if !root.isEmpty {
            body[root] = records
        } else {
            body["locations"] = records
        }
        body.merge(httpConfig.params) { $1 }

        let request = buildHTTPRequest(url: httpConfig.fullUrlWithParams(), method: httpConfig.method, headers: httpConfig.headersWithAuth(auth), body: body)
        doPost(request) { [weak self] response in
            self?.parseResponse(response)
        }
    }

    @objc public func doPost(_ request: URLRequest, callback: @escaping ([String: Any]) -> Void) {
        beginBackgroundFlushTask()
        NSLog("[BGGEO] HTTP POST -> \(request.url?.absoluteString ?? "?")")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            var result: [String: Any] = [:]
            if let httpResponse = response as? HTTPURLResponse {
                result["status"] = httpResponse.statusCode
                NSLog("[BGGEO] HTTP response status=\(httpResponse.statusCode)")
                if let data = data {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        result["data"] = json
                        BGRPC.sharedInstance().ingestHTTPResponse(withData: data, contentType: httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "")
                    }
                }
            }
            if let error = error {
                NSLog("[BGGEO] HTTP error: \(error.localizedDescription)")
                result["error"] = error.localizedDescription
            }
            callback(result)
        }.resume()
    }

    @objc public func parseResponse(_ response: [String: Any]) {
        let status = response["status"] as? Int ?? 0
        guard let m = metrics else { return }

        if (200...299).contains(status) {
            if m.lockedRecordsIsBatch {
                // Destroy ONLY the records actually sent in this batch (the
                // prefix slice), not the entire queue — otherwise records beyond
                // maxBatchSize were deleted without ever being POSTed. Then loop
                // to send the next batch until the queue is drained.
                let sent = m.currentBatchUuids
                _ = BGLocationDAO.sharedInstance().destroyAll(sent)
                m.synced += sent.count
                let sentSet = Set(sent)
                m.lockedRecords.removeAll { rec in
                    if let u = rec["uuid"] as? String { return sentSet.contains(u) }
                    return false
                }
                m.currentBatchUuids = []
                if m.lockedRecords.isEmpty {
                    finish(response, error: nil)
                } else {
                    scheduleBatchPost()
                }
            } else {
                if let uuid = m.lockedRecords[m.pages]["uuid"] as? String {
                    _ = BGLocationDAO.sharedInstance().destroy(uuid)
                    m.synced += 1
                }
                m.pages += 1
                if m.pages < m.lockedRecords.count {
                    schedulePost()
                } else {
                    finish(response, error: nil)
                }
            }
            fireConnectivityChangeEvent(true)
        } else if status == 401 && !m.authRefreshAttempted {
            m.authRefreshAttempted = true
            onAuthorization(response)
        } else {
            let error = NSError(domain: "BGHttpService", code: status, userInfo: [NSLocalizedDescriptionKey: "HTTP \(status)"])
            finish(response, error: error)
        }
    }

    @objc public func onAuthorization(_ response: [String: Any]) {
        metrics?.authRefreshAttempted = true
        continueFlush()
    }

    @objc public func finish(_ response: [String: Any], error: Error?) {
        let m = metrics
        resetFlushStateLocked()

        let event: [String: Any] = [
            "status": response["status"] ?? 0,
            "data": response["data"] ?? NSNull()
        ]
        BGEventBus.sharedInstance().emit(BGEventNames.http, payload: event)
        callback?()
        callback = nil

        if m != nil && bgTask != .invalid {
            stopWatchdog()
        }
    }

    @objc public func clearSyncedRecordsAndResetBusy() {
        syncedRecords.removeAll()
        isBusy = false
    }

    @objc public func resetFlushStateLocked() {
        isBusy = false
        metrics = nil
        syncedRecords.removeAll()
    }

    @objc public func isCurrentFlushId(_ flushId: String) -> Bool {
        return metrics?.flushId == flushId
    }

    // MARK: - Watchdog

    @objc public func armFlushWatchdog() {
        metrics?.watchdogArmed = true
        DispatchQueue.main.async {
            self.watchdogTimer?.invalidate()
            self.watchdogTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
                self?.resetFlushStateLocked()
                self?.endBackgroundFlushTask()
            }
        }
    }

    func stopWatchdog() {
        watchdogTimer?.invalidate()
        watchdogTimer = nil
        endBackgroundFlushTask()
    }

    private func beginBackgroundFlushTask() {
        let begin = {
            guard self.bgTask == .invalid else { return }
            self.bgTask = UIApplication.shared.beginBackgroundTask(withName: "BGHttpService.flush") { [weak self] in
                self?.resetFlushStateLocked()
                self?.endBackgroundFlushTask()
            }
        }
        if Thread.isMainThread {
            begin()
        } else {
            DispatchQueue.main.sync(execute: begin)
        }
    }

    private func endBackgroundFlushTask() {
        DispatchQueue.main.async {
            guard self.bgTask != .invalid else { return }
            UIApplication.shared.endBackgroundTask(self.bgTask)
            self.bgTask = .invalid
        }
    }

    // MARK: - Connectivity

    @objc public func onConnectivityChange(_ isReachable: Bool) {
        hasNetworkConnection = isReachable
        fireConnectivityChangeEvent(isReachable)
        if isReachable && !isBusy {
            flush()
        }
    }

    @objc public func fireConnectivityChangeEvent(_ connected: Bool) {
        BGEventBus.sharedInstance().emit(BGEventNames.connectivityChange, payload: ["connected": connected])
    }

    @objc public func fireAuthorizationEvent(_ response: [String: Any]) {
        BGEventBus.sharedInstance().emit(BGEventNames.authorization, payload: response)
    }

    // MARK: - Helpers

    private func buildRequest(for record: [String: Any], config: BGHttpConfig) -> URLRequest {
        var body: [String: Any] = [:]
        let root = config.rootProperty
        if !root.isEmpty {
            body[root] = record
        } else {
            body = record
            // A common location endpoint accepts flat coordinate aliases. Keep
            // the complete BGLocation payload while making the native request
            // compatible with the same REST contract used by the JS fallback.
            if let coords = record["coords"] as? [String: Any] {
                let latitude = coords["latitude"]
                let longitude = coords["longitude"]
                body["lat"] = latitude
                body["long"] = longitude
                body["latitude"] = latitude
                body["longitude"] = longitude
            }
        }
        body.merge(config.params) { $1 }
        return buildHTTPRequest(url: config.fullUrlWithParams(), method: config.method, headers: config.headersWithAuth(auth), body: body)
    }

    private func buildHTTPRequest(url: String, method: String, headers: [String: String], body: [String: Any]) -> URLRequest {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = BGConfig.sharedInstance().http.timeout
        return request
    }
}

import UIKit
