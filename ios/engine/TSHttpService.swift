import Foundation

@objc public class TSHttpSyncMetrics: NSObject {

    @objc public var flushId: String = UUID().uuidString
    @objc public var lockedRecords: [[String: Any]] = []
    @objc public var lockedRecordsIsBatch: Bool = false
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

@objc public class TSHttpService: NSObject {

    private static var _sharedInstance: TSHttpService?
    private static let instanceLock = NSLock()

    @objc public class func sharedInstance() -> TSHttpService {
        instanceLock.lock()
        defer { instanceLock.unlock() }
        if _sharedInstance == nil { _sharedInstance = TSHttpService() }
        return _sharedInstance!
    }

    // MARK: - State

    @objc public var isBusy: Bool = false
    @objc public var hasNetworkConnection: Bool = true
    @objc public var overrideSyncThreshold: Bool = false
    @objc public var autoSyncThreshold: Int = 0
    @objc public var auth: TSAuthorization?
    @objc public var reachability: TSReachability?
    @objc public var metrics: TSHttpSyncMetrics?
    @objc public var bgTask: UIBackgroundTaskIdentifier = .invalid
    @objc public var callback: (() -> Void)?
    @objc public var syncedRecords: [String] = []

    private let flushQueue = DispatchQueue(label: "TSHttpService.flush")
    private var watchdogTimer: Timer?

    @objc public override init() {
        super.init()
    }

    @objc public func startMonitoring() {
        reachability = TSReachability.reachability(forHostName: "google.com")
        reachability?.startMonitoring { [weak self] isReachable in
            self?.onConnectivityChange(isReachable)
        }
        registerConfigChangeHandlers()
    }

    @objc public func stopMonitoring() {
        reachability?.stopMonitoring()
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

    @objc public func beginFlush(withCallback callback: (([String: Any]) -> Void)?, overrideSyncThreshold override: Bool, error: UnsafeMutablePointer<NSError?>?) {
        flushQueue.async { [weak self] in
            guard let self = self else { return }
            guard !self.isBusy else { return }
            guard self.hasNetworkConnection else { return }

            let dao = TSLocationDAO.sharedInstance()
            let records = dao.allWithLocking(true)
            guard !records.isEmpty else {
                callback?([:])
                return
            }

            let threshold = self.autoSyncThreshold
            guard override || records.count >= threshold || threshold == 0 else { return }

            self.isBusy = true
            let m = TSHttpSyncMetrics()
            m.lockedRecords = records
            m.queuedBefore = records.count
            self.metrics = m

            self.armFlushWatchdog()
            self.continueFlush()
        }
    }

    @objc public func continueFlush() {
        guard let m = metrics else { resetFlushStateLocked(); return }

        let config = TSConfig.sharedInstance()
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
        let config = TSConfig.sharedInstance().http
        let maxBatch = config.effectiveBatchSize
        let slice = maxBatch > 0 ? Array(m.lockedRecords.prefix(maxBatch)) : m.lockedRecords
        m.lockedRecordsIsBatch = true
        postBatch(slice)
    }

    @objc public func post(_ record: [String: Any]) {
        let config = TSConfig.sharedInstance()
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
        let config = TSConfig.sharedInstance()
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
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            var result: [String: Any] = [:]
            if let httpResponse = response as? HTTPURLResponse {
                result["status"] = httpResponse.statusCode
                if let data = data {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        result["data"] = json
                        TSRPC.sharedInstance().ingestHTTPResponse(withData: data, contentType: httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "")
                    }
                }
            }
            if let error = error { result["error"] = error.localizedDescription }
            callback(result)
        }.resume()
    }

    @objc public func parseResponse(_ response: [String: Any]) {
        let status = response["status"] as? Int ?? 0
        guard let m = metrics else { return }

        if status == 200 || status == 201 {
            let uuids = m.lockedRecords.compactMap { $0["uuid"] as? String }
            if m.lockedRecordsIsBatch {
                _ = TSLocationDAO.sharedInstance().destroyAll(uuids)
                m.synced += uuids.count
                finish(response, error: nil)
            } else {
                if let uuid = m.lockedRecords[m.pages]["uuid"] as? String {
                    _ = TSLocationDAO.sharedInstance().destroy(uuid)
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
            let error = NSError(domain: "TSHttpService", code: status, userInfo: [NSLocalizedDescriptionKey: "HTTP \(status)"])
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
        TSEventBus.sharedInstance().emit(TSEventNames.http, payload: event)
        callback?()
        callback = nil

        if let bgTask = (m != nil ? bgTask : .invalid) as UIBackgroundTaskIdentifier?, bgTask != .invalid {
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
            }
        }
    }

    func stopWatchdog() {
        watchdogTimer?.invalidate()
        watchdogTimer = nil
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
        TSEventBus.sharedInstance().emit(TSEventNames.connectivityChange, payload: ["connected": connected])
    }

    @objc public func fireAuthorizationEvent(_ response: [String: Any]) {
        TSEventBus.sharedInstance().emit(TSEventNames.authorization, payload: response)
    }

    // MARK: - Helpers

    private func buildRequest(for record: [String: Any], config: TSHttpConfig) -> URLRequest {
        var body: [String: Any] = [:]
        let root = config.rootProperty
        if !root.isEmpty {
            body[root] = record
        } else {
            body = record
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
        request.timeoutInterval = TSConfig.sharedInstance().http.timeout
        return request
    }
}

import UIKit
