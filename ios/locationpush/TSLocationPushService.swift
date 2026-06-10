//
//  TSLocationPushService.swift
//
//  The principal class of the iOS Location Push Service Extension
//  (CLLocationPushServiceExtension, iOS 15+).
//
//  ── WHAT THIS IS ──────────────────────────────────────────────────────────
//  When your server sends an APNs push (apns-push-type: location, apns-topic:
//  <bundle-id>.location-query) to the device's location-push token, iOS launches
//  THIS extension in a separate, short-lived process — even if the host app has
//  been force-quit. The extension grabs one location fix and ships it to your
//  server, then signals completion and is torn down.
//
//  ── DELIVERY ──────────────────────────────────────────────────────────────
//  The push payload carries a `location-query` id. Its presence means "capture
//  and report a location now". We:
//    1. requestLocation() — one GPS fix.
//    2. Try Socket.IO (`location:update`) first, if socket config is present.
//    3. Fall back to REST POST to the configured `url`.
//  The captured location-query id is echoed back so the server can correlate.
//
//  ── REQUIREMENTS ──────────────────────────────────────────────────────────
//    • Apple-approved `com.apple.developer.location.push` entitlement.
//    • App Group shared with the host app (see TSLocationPushShared).
//    • Host app calls startMonitoringLocationPushes + ships the token to server.
//    • "Always" location authorization.
//
//  ~30s wall-clock budget. The socket attempt is tightly timed so REST always
//  has room to run.
//

import CoreLocation
import Foundation
import os.log

@available(iOS 15.0, *)
@objc(TSLocationPushService)
public final class TSLocationPushService: NSObject, CLLocationPushServiceExtension {

    private var completion: (() -> Void)?
    private var manager: CLLocationManager?
    private var fetcher: TSLocationPushFetcher?

    public override init() {
        super.init()
    }

    public func didReceiveLocationPushPayload(
        _ payload: [String: Any],
        completion: @escaping () -> Void
    ) {
        TSLocationPushLog.log("didReceiveLocationPushPayload: \(payload)")
        self.completion = completion

        let queryId = Self.extractLocationQueryId(from: payload)
        guard let queryId = queryId else {
            // No location-query id → nothing to report. Finish cleanly.
            TSLocationPushLog.log("no location-query id in payload — ignoring")
            finish()
            return
        }
        TSLocationPushLog.log("location-query id = \(queryId)")

        let fetcher = TSLocationPushFetcher(queryId: queryId) { [weak self] in
            self?.finish()
        }
        self.fetcher = fetcher

        let mgr = CLLocationManager()
        mgr.delegate = fetcher
        mgr.desiredAccuracy = kCLLocationAccuracyBest
        self.manager = mgr
        mgr.requestLocation() // one-shot
    }

    public func serviceExtensionWillTerminate() {
        TSLocationPushLog.log("serviceExtensionWillTerminate — flushing")
        fetcher?.flushPendingIfNeeded()
        finish()
    }

    private func finish() {
        guard let completion = completion else { return }
        self.completion = nil
        self.manager = nil
        self.fetcher = nil
        completion()
    }

    /// Pull the location-query id out of the push payload. Accepts several key
    /// spellings so it survives server-side naming differences.
    static func extractLocationQueryId(from payload: [String: Any]) -> String? {
        let candidates = ["location-query", "locationQuery", "location_query",
                          "locationQueryId", "queryId", "query-id"]
        // Top level, then nested under "aps".
        var scopes: [[String: Any]] = [payload]
        if let aps = payload["aps"] as? [String: Any] { scopes.append(aps) }
        for scope in scopes {
            for key in candidates {
                if let value = scope[key] {
                    if let s = value as? String, !s.isEmpty { return s }
                    if let n = value as? NSNumber { return n.stringValue }
                }
            }
        }
        return nil
    }
}

// MARK: - Location fetcher + delivery

@available(iOS 15.0, *)
final class TSLocationPushFetcher: NSObject, CLLocationManagerDelegate {

    private let queryId: String
    private let completion: () -> Void
    private var didComplete = false
    private var socketClient: TSLocationPushSocketClient?

    init(queryId: String, completion: @escaping () -> Void) {
        self.queryId = queryId
        self.completion = completion
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard !didComplete, let location = locations.last else { return }
        TSLocationPushLog.log("got location \(location.coordinate.latitude),\(location.coordinate.longitude)")
        deliver(location: location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard !didComplete else { return }
        TSLocationPushLog.log("CLLocationManager failed: \(error.localizedDescription)")
        complete()
    }

    func flushPendingIfNeeded() {
        guard !didComplete else { return }
        TSLocationPushLog.log("terminated before location fix arrived")
    }

    // MARK: Delivery — socket first, REST fallback

    private func deliver(location: CLLocation) {
        guard !didComplete else { return }
        didComplete = true

        guard let defaults = TSLocationPushShared.sharedDefaults() else {
            TSLocationPushLog.log("App Group not configured — cannot deliver")
            complete()
            return
        }

        if let socketUrlString = defaults.string(forKey: TSLocationPushShared.keySocketUrl),
           !socketUrlString.isEmpty,
           let socketUrl = URL(string: socketUrlString) {
            let path  = defaults.string(forKey: TSLocationPushShared.keySocketPath) ?? "/socket.io"
            let event = defaults.string(forKey: TSLocationPushShared.keySocketEvent) ?? "location:update"
            let token = defaults.string(forKey: TSLocationPushShared.keySocketAuthToken)
            let timeout = defaults.object(forKey: TSLocationPushShared.keySocketTimeout) as? Double ?? 8.0

            TSLocationPushLog.log("attempting socket delivery → \(socketUrlString)\(path)")
            let client = TSLocationPushSocketClient(config: .init(
                url: socketUrl, path: path, event: event,
                authToken: token, timeout: timeout
            ))
            self.socketClient = client
            client.emit(socketPayload(location: location)) { [weak self] ok in
                guard let self = self else { return }
                if ok {
                    TSLocationPushLog.log("✅ delivered via socket")
                    self.complete()
                } else {
                    TSLocationPushLog.log("socket failed → REST fallback")
                    self.postViaRest(location: location, defaults: defaults)
                }
            }
            return
        }

        postViaRest(location: location, defaults: defaults)
    }

    private func postViaRest(location: CLLocation, defaults: UserDefaults) {
        let headers      = defaults.dictionary(forKey: TSLocationPushShared.keyHeaders) as? [String: String] ?? [:]
        // Same JWT the socket uses; fall back to the http-config access token.
        let bearer = defaults.string(forKey: TSLocationPushShared.keySocketAuthToken)
            ?? defaults.string(forKey: TSLocationPushShared.keyAccessToken)

        let url: URL
        let body: [String: Any]

        // Preferred fallback: POST {latitude, longitude, fcmToken, userCurrentTime}
        // to /api/location/fallback (the backend's socket-failure endpoint).
        if let fallbackString = defaults.string(forKey: TSLocationPushShared.keyFallbackUrl),
           !fallbackString.isEmpty, let fallbackUrl = URL(string: fallbackString) {
            url = fallbackUrl
            body = [
                "latitude": location.coordinate.latitude,
                "longitude": location.coordinate.longitude,
                "fcmToken": defaults.string(forKey: TSLocationPushShared.keyFcmToken) ?? "",
                "userCurrentTime": Self.currentTimeHHmm(),
                "location_query_id": queryId
            ]
            TSLocationPushLog.log("REST fallback → \(fallbackString)")
        } else {
            // Generic record POST to the configured http.url (legacy path).
            let urlString = defaults.string(forKey: TSLocationPushShared.keyUrl) ?? ""
            guard !urlString.isEmpty, let generic = URL(string: urlString) else {
                TSLocationPushLog.log("no REST url configured — giving up")
                complete()
                return
            }
            url = generic
            let extras       = defaults.dictionary(forKey: TSLocationPushShared.keyExtras) ?? [:]
            let params       = defaults.dictionary(forKey: TSLocationPushShared.keyParams) ?? [:]
            let rootProperty = defaults.string(forKey: TSLocationPushShared.keyRootProperty) ?? "location"
            let locationDict = restLocation(location: location, extras: extras)
            var generated: [String: Any] = [:]
            if rootProperty.isEmpty || rootProperty == "." {
                generated = locationDict
            } else {
                generated[rootProperty] = locationDict
            }
            for (key, value) in params { generated[key] = value }
            generated["location_query_id"] = queryId
            body = generated
            TSLocationPushLog.log("REST → \(urlString)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = bearer, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])

        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            if let error = error {
                TSLocationPushLog.log("REST error: \(error.localizedDescription)")
            } else if let http = response as? HTTPURLResponse {
                TSLocationPushLog.log("REST HTTP \(http.statusCode)")
            }
            self?.complete()
        }.resume()
    }

    private static func currentTimeHHmm() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date())
    }

    // MARK: Payloads

    /// Flat payload the JS socket server expects (mirrors `location:update`).
    private func socketPayload(location: CLLocation) -> [String: Any] {
        [
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "accuracy": max(location.horizontalAccuracy, 0),
            "speed": location.speed,
            "heading": location.course,
            "altitude": location.altitude,
            "timestamp": Self.iso8601(location.timestamp),
            "location_query_id": queryId,
            "source": "location-push"
        ]
    }

    private func restLocation(location: CLLocation, extras: [String: Any]) -> [String: Any] {
        var coords: [String: Any] = [
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "accuracy": max(location.horizontalAccuracy, 0),
            "speed": location.speed,
            "speed_accuracy": location.speedAccuracy,
            "heading": location.course,
            "heading_accuracy": location.courseAccuracy,
            "altitude": location.altitude,
            "altitude_accuracy": location.verticalAccuracy
        ]
        if let floor = location.floor { coords["floor"] = floor.level }

        var mergedExtras: [String: Any] = ["LocationPushService": true, "location_query_id": queryId]
        for (key, value) in extras { mergedExtras[key] = value }

        return [
            "coords": coords,
            // Flat aliases for servers that read lat/long at the record root.
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "lat": location.coordinate.latitude,
            "long": location.coordinate.longitude,
            "timestamp": Self.iso8601(location.timestamp),
            "is_moving": false,
            "event": "location-push",
            "extras": mergedExtras
        ]
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private func complete() {
        socketClient = nil
        completion()
    }
}

// MARK: - Logging

@available(iOS 15.0, *)
enum TSLocationPushLog {
    private static let logger = OSLog(subsystem: "com.bggeolocation.locationpush", category: "LocationPush")
    static func log(_ message: String) {
        os_log("%{public}@", log: logger, type: .info, message)
        NSLog("[BGGEO][PushExt] \(message)")
    }
}
