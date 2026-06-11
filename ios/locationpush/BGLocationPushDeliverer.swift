//
//  BGLocationPushDeliverer.swift
//
//  Shared, JS-independent delivery for a push-triggered location. Used by BOTH:
//    • BGLocationPushService (the kill-state extension, separate process)
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
@objc public final class BGLocationPushDeliverer: NSObject {

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
        let job = BGLocationPushDeliveryJob(
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
private final class BGLocationPushDeliveryJob {
    let latitude, longitude, accuracy, speed, heading, altitude: Double
    let timestampISO: String
    let queryId: String
    let completion: (Bool) -> Void
    private var socketClient: BGLocationPushSocketClient?
    private var retained: BGLocationPushDeliveryJob?

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
        guard let defaults = BGLocationPushShared.sharedDefaults() else {
            BGLocationPushLog.log("no shared config — cannot deliver")
            finish(false)
            return
        }

        if let socketUrlString = defaults.string(forKey: BGLocationPushShared.keySocketUrl),
           !socketUrlString.isEmpty, let socketUrl = URL(string: socketUrlString) {
            let path  = defaults.string(forKey: BGLocationPushShared.keySocketPath) ?? "/socket.io"
            let event = defaults.string(forKey: BGLocationPushShared.keySocketEvent) ?? "location:update"
            let token = defaults.string(forKey: BGLocationPushShared.keySocketAuthToken)
            let timeout = defaults.object(forKey: BGLocationPushShared.keySocketTimeout) as? Double ?? 8.0

            BGLocationPushLog.log("socket delivery → \(socketUrlString)\(path)")
            let client = BGLocationPushSocketClient(config: .init(
                url: socketUrl, path: path, event: event, authToken: token, timeout: timeout
            ))
            socketClient = client
            client.emit(payload(defaults: defaults, default: socketPayload())) { [weak self] ok in
                guard let self = self else { return }
                if ok {
                    BGLocationPushLog.log("✅ delivered via socket")
                    self.finish(true)
                } else {
                    BGLocationPushLog.log("socket failed → REST fallback")
                    self.postViaRest(defaults: defaults)
                }
            }
            return
        }

        postViaRest(defaults: defaults)
    }

    private func postViaRest(defaults: UserDefaults) {
        let headers = defaults.dictionary(forKey: BGLocationPushShared.keyHeaders) as? [String: String] ?? [:]
        let bearer = defaults.string(forKey: BGLocationPushShared.keySocketAuthToken)
            ?? defaults.string(forKey: BGLocationPushShared.keyAccessToken)

        let url: URL
        let body: [String: Any]

        if let fallbackString = defaults.string(forKey: BGLocationPushShared.keyFallbackUrl),
           !fallbackString.isEmpty, let fallbackUrl = URL(string: fallbackString) {
            url = fallbackUrl
            let defaultBody: [String: Any] = [
                "latitude": latitude,
                "longitude": longitude,
                "fcmToken": defaults.string(forKey: BGLocationPushShared.keyFcmToken) ?? "",
                "userCurrentTime": BGLocationPushDeliverer.currentTimeHHmm(),
                "location_query_id": queryId
            ]
            body = payload(defaults: defaults, default: defaultBody)
            BGLocationPushLog.log("REST fallback → \(fallbackString)")
        } else {
            let urlString = defaults.string(forKey: BGLocationPushShared.keyUrl) ?? ""
            guard !urlString.isEmpty, let generic = URL(string: urlString) else {
                BGLocationPushLog.log("no REST url configured — giving up")
                finish(false)
                return
            }
            url = generic
            let rootProperty = defaults.string(forKey: BGLocationPushShared.keyRootProperty) ?? "location"
            let params = defaults.dictionary(forKey: BGLocationPushShared.keyParams) ?? [:]
            let locationDict = restLocation(defaults: defaults)
            var generated: [String: Any] = [:]
            if rootProperty.isEmpty || rootProperty == "." { generated = locationDict }
            else { generated[rootProperty] = locationDict }
            for (k, v) in params { generated[k] = v }
            generated["location_query_id"] = queryId
            body = generated
            BGLocationPushLog.log("REST → \(urlString)")
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
                BGLocationPushLog.log("REST error: \(error.localizedDescription)")
                self?.finish(false)
            } else if let http = response as? HTTPURLResponse {
                BGLocationPushLog.log("REST HTTP \(http.statusCode)")
                self?.finish((200...299).contains(http.statusCode))
            } else {
                self?.finish(false)
            }
        }.resume()
    }

    /// Resolve the upload body: if the host supplied a `payloadTemplate` via
    /// setLocationPushConfig, render it (substituting {tokens} with live values);
    /// otherwise use the built-in `default` payload.
    private func payload(defaults: UserDefaults, default fallback: [String: Any]) -> [String: Any] {
        guard let template = defaults.dictionary(forKey: BGLocationPushShared.keyPayloadTemplate) else {
            return fallback
        }
        return (render(template) as? [String: Any]) ?? fallback
    }

    /// Live values that template tokens like "{latitude}" / "{fcmToken}" map to.
    private func tokenValues() -> [String: Any] {
        let fcm = BGLocationPushShared.sharedDefaults()?
            .string(forKey: BGLocationPushShared.keyFcmToken) ?? ""
        let time = BGLocationPushDeliverer.currentTimeHHmm()
        return [
            "latitude": latitude, "lat": latitude,
            "longitude": longitude, "long": longitude,
            "accuracy": max(accuracy, 0),
            "speed": speed, "heading": heading, "altitude": altitude,
            "timestamp": timestampISO,
            "fcmToken": fcm, "fcm_token": fcm,
            "queryId": queryId, "locationQueryId": queryId, "location_query_id": queryId,
            "userCurrentTime": time, "user_current_time": time, "time": time,
            "deviceType": "ios", "device_type": "ios"
        ]
    }

    /// Recursively substitute tokens in a template value. A string that is exactly
    /// one token ("{latitude}") yields the typed value (Double/String); a string
    /// with inline tokens is interpolated; dicts/arrays recurse; other values pass
    /// through unchanged.
    private func render(_ value: Any) -> Any {
        let tokens = tokenValues()
        if let dict = value as? [String: Any] {
            var out: [String: Any] = [:]
            for (k, v) in dict { out[k] = render(v) }
            return out
        }
        if let arr = value as? [Any] {
            return arr.map { render($0) }
        }
        if let s = value as? String {
            if s.hasPrefix("{"), s.hasSuffix("}"),
               !s.dropFirst().dropLast().contains("{"),
               let typed = tokens[String(s.dropFirst().dropLast())] {
                return typed // exact single-token → typed value (keeps numbers numeric)
            }
            var result = s
            for (name, val) in tokens {
                result = result.replacingOccurrences(of: "{\(name)}", with: "\(val)")
            }
            return result
        }
        return value
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
        let extras = defaults.dictionary(forKey: BGLocationPushShared.keyExtras) ?? [:]
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
