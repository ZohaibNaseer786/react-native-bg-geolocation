//
//  TSLocationPushService.swift
//
//  The principal class of the iOS Location Push Service Extension
//  (CLLocationPushServiceExtension, iOS 15+).
//
//  ── WHAT THIS IS ──────────────────────────────────────────────────────────
//  When your server sends an APNs push to the device's *location-push* token,
//  iOS launches THIS extension in a separate, short-lived process — even if the
//  host app has been force-quit / terminated. The extension grabs one location
//  fix and POSTs it to your server, then signals completion and is torn down.
//
//  This is the production mechanism rideshare / delivery apps use to keep
//  tracking a user after the app is killed. It does NOT load React Native or the
//  full TSLocationManager engine — it must stay lightweight and only use
//  extension-safe APIs (CoreLocation + URLSession + UserDefaults).
//
//  ── REQUIREMENTS ──────────────────────────────────────────────────────────
//    • Apple-approved entitlement `com.apple.developer.location.push` on BOTH
//      the host app and this extension.
//    • App Group shared between host app and extension (see TSLocationPushShared).
//    • The host app must call `startMonitoringLocationPushesWithCompletion`
//      and ship the returned token to your server.
//    • The user must have granted "Always" location authorization.
//
//  The extension has a hard ~30s wall-clock budget. requestLocation() + the
//  HTTP POST must finish within it, else `serviceExtensionWillTerminate` fires.
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

    // Called by iOS when an APNs location push arrives for this device.
    public func didReceiveLocationPushPayload(
        _ payload: [String: Any],
        completion: @escaping () -> Void
    ) {
        TSLocationPushLog.log("didReceiveLocationPushPayload: \(payload)")
        self.completion = completion

        // Build a single-shot fetcher that grabs a location then POSTs it.
        let fetcher = TSLocationPushFetcher(payload: payload) { [weak self] in
            self?.finish()
        }
        self.fetcher = fetcher

        let mgr = CLLocationManager()
        mgr.delegate = fetcher
        mgr.desiredAccuracy = kCLLocationAccuracyBest
        self.manager = mgr

        // One-shot delivery: iOS sends a single fix to didUpdateLocations.
        mgr.requestLocation()
    }

    // iOS is about to terminate the extension (time budget exhausted). Be clean.
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
}

// MARK: - Location fetcher + HTTP poster

@available(iOS 15.0, *)
final class TSLocationPushFetcher: NSObject, CLLocationManagerDelegate {

    private let payload: [String: Any]
    private let completion: () -> Void
    private var didComplete = false

    init(payload: [String: Any], completion: @escaping () -> Void) {
        self.payload = payload
        self.completion = completion
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard !didComplete, let location = locations.last else { return }
        TSLocationPushLog.log("got location \(location.coordinate.latitude),\(location.coordinate.longitude)")
        post(location: location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard !didComplete else { return }
        TSLocationPushLog.log("CLLocationManager failed: \(error.localizedDescription)")
        complete()
    }

    // Called from serviceExtensionWillTerminate if we never got a fix.
    func flushPendingIfNeeded() {
        guard !didComplete else { return }
        TSLocationPushLog.log("terminated before location fix arrived")
    }

    // MARK: HTTP

    private func post(location: CLLocation) {
        guard !didComplete else { return }
        didComplete = true

        guard let defaults = TSLocationPushShared.sharedDefaults() else {
            TSLocationPushLog.log("App Group not configured — cannot read server config")
            complete()
            return
        }

        let urlString = defaults.string(forKey: TSLocationPushShared.keyUrl) ?? ""
        guard !urlString.isEmpty, let url = URL(string: urlString) else {
            TSLocationPushLog.log("no server URL configured — skipping POST")
            complete()
            return
        }

        let method       = defaults.string(forKey: TSLocationPushShared.keyMethod) ?? "POST"
        let headers      = defaults.dictionary(forKey: TSLocationPushShared.keyHeaders) as? [String: String] ?? [:]
        let params       = defaults.dictionary(forKey: TSLocationPushShared.keyParams) ?? [:]
        let extras       = defaults.dictionary(forKey: TSLocationPushShared.keyExtras) ?? [:]
        let rootProperty = defaults.string(forKey: TSLocationPushShared.keyRootProperty) ?? "location"
        let accessToken  = defaults.string(forKey: TSLocationPushShared.keyAccessToken)

        let locationDict = Self.buildLocation(location: location, extras: extras)

        // Compose the request body. When rootProperty is set, nest the location
        // under it (matches the engine's HTTP format) and merge top-level params.
        var body: [String: Any] = [:]
        if rootProperty.isEmpty || rootProperty == "." {
            body = locationDict
        } else {
            body[rootProperty] = locationDict
        }
        for (key, value) in params { body[key] = value }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = accessToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])

        TSLocationPushLog.log("POST \(method) -> \(urlString)")

        let task = URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            if let error = error {
                TSLocationPushLog.log("HTTP error: \(error.localizedDescription)")
            } else if let http = response as? HTTPURLResponse {
                TSLocationPushLog.log("HTTP \(http.statusCode)")
            }
            self?.complete()
        }
        task.resume()
    }

    private static func buildLocation(location: CLLocation, extras: [String: Any]) -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

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
        if location.floor != nil {
            coords["floor"] = location.floor?.level as Any
        }

        var mergedExtras: [String: Any] = ["LocationPushService": true]
        for (key, value) in extras { mergedExtras[key] = value }

        return [
            "coords": coords,
            "timestamp": formatter.string(from: location.timestamp),
            "is_moving": false,
            "event": "location-push",
            "extras": mergedExtras
        ]
    }

    private func complete() {
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
