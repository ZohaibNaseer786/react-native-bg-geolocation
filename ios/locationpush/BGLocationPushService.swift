//
//  BGLocationPushService.swift
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
//    • App Group shared with the host app (see BGLocationPushShared).
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
@objc(BGLocationPushService)
public final class BGLocationPushService: NSObject, CLLocationPushServiceExtension {

    private var completion: (() -> Void)?
    private var manager: CLLocationManager?
    private var fetcher: BGLocationPushFetcher?

    public override init() {
        super.init()
    }

    public func didReceiveLocationPushPayload(
        _ payload: [String: Any],
        completion: @escaping () -> Void
    ) {
        BGLocationPushLog.log("didReceiveLocationPushPayload: \(payload)")
        self.completion = completion

        let queryId = Self.extractLocationQueryId(from: payload)
        guard let queryId = queryId else {
            // No location-query id → nothing to report. Finish cleanly.
            BGLocationPushLog.log("no location-query id in payload — ignoring")
            finish()
            return
        }
        BGLocationPushLog.log("location-query id = \(queryId)")

        let fetcher = BGLocationPushFetcher(queryId: queryId) { [weak self] in
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
        BGLocationPushLog.log("serviceExtensionWillTerminate — flushing")
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
final class BGLocationPushFetcher: NSObject, CLLocationManagerDelegate {

    private let queryId: String
    private let completion: () -> Void
    private var didComplete = false

    init(queryId: String, completion: @escaping () -> Void) {
        self.queryId = queryId
        self.completion = completion
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard !didComplete, let location = locations.last else { return }
        didComplete = true
        BGLocationPushLog.log("got location \(location.coordinate.latitude),\(location.coordinate.longitude)")
        // Delegate to the shared native deliverer (socket → REST), so the
        // extension and the in-app handler use identical delivery logic.
        BGLocationPushDeliverer.deliver(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            accuracy: max(location.horizontalAccuracy, 0),
            speed: location.speed,
            heading: location.course,
            altitude: location.altitude,
            timestampISO: Self.iso8601(location.timestamp),
            queryId: queryId
        ) { [weak self] _ in
            self?.completion()
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard !didComplete else { return }
        didComplete = true
        BGLocationPushLog.log("CLLocationManager failed: \(error.localizedDescription)")
        completion()
    }

    func flushPendingIfNeeded() {
        guard !didComplete else { return }
        BGLocationPushLog.log("terminated before location fix arrived")
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
