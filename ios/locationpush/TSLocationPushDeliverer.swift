//
//  TSLocationPushDeliverer.swift
//
//  Shared, JS-independent delivery for a push-triggered location. Used by BOTH:
//    • TSLocationPushService (the kill-state extension, separate process)
//    • BgGeolocation module (the in-app background-push handler)
//
//  Push-triggered delivery CANNOT depend on the React Native bridge: when iOS
//  wakes the app (or the extension) from a killed/suspended state, JS is often
//  not booted and emitted events are dropped. So the SDK delivers natively here
//  — socket first, then REST fallback — reading config the host app provided via
//  BackgroundGeolocation.setLocationPushConfig({...}).
//
//  Extension-safe: Foundation + URLSession only.
//

import CoreLocation
import Foundation

@available(iOS 15.0, *)
@objc public final class TSLocationPushDeliverer: NSObject {

    /// Deliver a location captured for `queryId`. Tries the socket channel first
    /// (if configured), then the REST fallback. `completion(true)` on the first
    /// channel that succeeds, `completion(false)` if everything fails.
    @objc public static func deliver(
        latitude: Double,
        longitude: Double,
        accuracy: Double,
        speed: Double,
        heading: Double,
        altitude: Double,
        timestampISO: String,
        queryId: String,
        completion: @escaping (Bool) -> Void
    ) {
        let job = TSLocationPushDeliveryJob(
            latitude: latitude, longitude: longitude, accuracy: accuracy,
            speed: speed, heading: heading, altitude: altitude,
            timestampISO: timestampISO, queryId: queryId, completion: completion
        )
        job.start()
    }

    static func currentTimeHHmm() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date())
    }
}

@available(iOS 15.0, *)
private final class TSLocationPushDeliveryJob {
    let latitude, longitude, accuracy, speed, heading, altitude: Double
    let timestampISO: String
    let queryId: String
    let completion: (Bool) -> Void
    private var socketClient: TSLocationPushSocketClient?
    private var retained: TSLocationPushDeliveryJob?

    init(latitude: Double, longitude: Double, accuracy: Double, speed: Double,
         heading: Double, altitude: Double, timestampISO: String,
         queryId: String, completion: @escaping (Bool) -> Void) {
        self.latitude = latitude; self.longitude = longitude
        self.accuracy = accuracy; self.speed = speed
        self.heading = heading; self.altitude = altitude
        self.timestampISO = timestampISO; self.queryId = queryId
        self.completion = completion
    }

    func start() {
        retained = self // keep alive across async callbacks
        guard let defaults = TSLocationPushShared.sharedDefaults() else {
            TSLocationPushLog.log("no shared config — cannot deliver")
            finish(false)
            return
        }

        if let socketUrlString = defaults.string(forKey: TSLocationPushShared.keySocketUrl),
           !socketUrlString.isEmpty, let socketUrl = URL(string: socketUrlString) {
            let path  = defaults.string(forKey: TSLocationPushShared.keySocketPath) ?? "/socket.io"
            let event = defaults.string(forKey: TSLocationPushShared.keySocketEvent) ?? "location:update"
            let token = defaults.string(forKey: TSLocationPushShared.keySocketAuthToken)
            let timeout = defaults.object(forKey: TSLocationPushShared.keySocketTimeout) as? Double ?? 8.0

            TSLocationPushLog.log("socket delivery → \(socketUrlString)\(path)")
            let client = TSLocationPushSocketClient(config: .init(
                url: socketUrl, path: path, event: event, authToken: token, timeout: timeout
            ))
            socketClient = client
            client.emit(socketPayload()) { [weak self] ok in
                guard let self = self else { return }
                if ok {
                    TSLocationPushLog.log("✅ delivered via socket")
                    self.finish(true)
                } else {
                    TSLocationPushLog.log("socket failed → REST fallback")
                    self.postViaRest(defaults: defaults)
                }
            }
            return
        }

        postViaRest(defaults: defaults)
    }

    private func postViaRest(defaults: UserDefaults) {
        let headers = defaults.dictionary(forKey: TSLocationPushShared.keyHeaders) as? [String: String] ?? [:]
        let bearer = defaults.string(forKey: TSLocationPushShared.keySocketAuthToken)
            ?? defaults.string(forKey: TSLocationPushShared.keyAccessToken)

        let url: URL
        let body: [String: Any]

        if let fallbackString = defaults.string(forKey: TSLocationPushShared.keyFallbackUrl),
           !fallbackString.isEmpty, let fallbackUrl = URL(string: fallbackString) {
            url = fallbackUrl
            body = [
                "latitude": latitude,
                "longitude": longitude,
                "fcmToken": defaults.string(forKey: TSLocationPushShared.keyFcmToken) ?? "",
                "userCurrentTime": TSLocationPushDeliverer.currentTimeHHmm(),
                "location_query_id": queryId
            ]
            TSLocationPushLog.log("REST fallback → \(fallbackString)")
        } else {
            let urlString = defaults.string(forKey: TSLocationPushShared.keyUrl) ?? ""
            guard !urlString.isEmpty, let generic = URL(string: urlString) else {
                TSLocationPushLog.log("no REST url configured — giving up")
                finish(false)
                return
            }
            url = generic
            let rootProperty = defaults.string(forKey: TSLocationPushShared.keyRootProperty) ?? "location"
            let params = defaults.dictionary(forKey: TSLocationPushShared.keyParams) ?? [:]
            let locationDict = restLocation(defaults: defaults)
            var generated: [String: Any] = [:]
            if rootProperty.isEmpty || rootProperty == "." { generated = locationDict }
            else { generated[rootProperty] = locationDict }
            for (k, v) in params { generated[k] = v }
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
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])

        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            if let error = error {
                TSLocationPushLog.log("REST error: \(error.localizedDescription)")
                self?.finish(false)
            } else if let http = response as? HTTPURLResponse {
                TSLocationPushLog.log("REST HTTP \(http.statusCode)")
                self?.finish((200...299).contains(http.statusCode))
            } else {
                self?.finish(false)
            }
        }.resume()
    }

    private func socketPayload() -> [String: Any] {
        [
            "latitude": latitude, "longitude": longitude,
            "accuracy": max(accuracy, 0), "speed": speed, "heading": heading,
            "altitude": altitude, "timestamp": timestampISO,
            "location_query_id": queryId, "source": "location-push"
        ]
    }

    private func restLocation(defaults: UserDefaults) -> [String: Any] {
        let extras = defaults.dictionary(forKey: TSLocationPushShared.keyExtras) ?? [:]
        var mergedExtras: [String: Any] = ["LocationPushService": true, "location_query_id": queryId]
        for (k, v) in extras { mergedExtras[k] = v }
        return [
            "coords": [
                "latitude": latitude, "longitude": longitude,
                "accuracy": max(accuracy, 0), "speed": speed,
                "heading": heading, "altitude": altitude
            ],
            "latitude": latitude, "longitude": longitude,
            "lat": latitude, "long": longitude,
            "timestamp": timestampISO, "is_moving": false,
            "event": "location-push", "extras": mergedExtras
        ]
    }

    private func finish(_ success: Bool) {
        let cb = completion
        socketClient = nil
        let keepAlive = retained
        retained = nil
        cb(success)
        _ = keepAlive
    }
}
