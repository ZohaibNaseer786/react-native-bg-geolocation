//
//  BGLocationPushShared.swift
//
//  Constants shared between the host app (BGLocationManager engine) and the
//  CLLocationPushServiceExtension. Because the extension runs in a SEPARATE
//  process, the only channel between them is an App Group shared UserDefaults
//  suite. Both sides MUST agree on the suite name and the keys below.
//
//  This file is compiled into BOTH:
//    1. The `BgGeolocation` pod (so BGLocationManager can WRITE the config)
//    2. The Location Push Service Extension target (so it can READ the config)
//
//  ── HOST-APP INTEGRATION ──────────────────────────────────────────────────
//  Consumers of this package must:
//    • Create an App Group with the identifier in `appGroupIdentifier` below
//      (or override it — see BGLocationPushShared.resolveAppGroupIdentifier()).
//    • Add that App Group to BOTH the main app target and the extension target.
//  If you use a different App Group id, change `defaultAppGroupIdentifier` here
//  (it is the single source of truth) and rebuild.
//

import Foundation
import os.log

// Shared logger for all location-push code (extension + in-app). Compiled into
// both the pod and the extension target via BGLocationPushShared.swift.
enum BGLocationPushLog {
    private static let logger = OSLog(subsystem: "com.bggeolocation.locationpush", category: "LocationPush")
    static func log(_ message: String) {
        os_log("%{public}@", log: logger, type: .info, message)
        NSLog("[BGGEO][PushExt] \(message)")
    }
}

@objc public final class BGLocationPushShared: NSObject {

    /// The default App Group identifier. The example app uses this value; it is
    /// the single place to change if you adopt a different group id.
    public static let defaultAppGroupIdentifier = "group.com.masjidpilot.staging"

    // UserDefaults keys written by the host app and read by the extension.
    public static let keyAppGroup       = "BGLocationPush_appGroup"
    public static let keyUrl            = "BGLocationPush_url"
    public static let keyMethod         = "BGLocationPush_method"
    public static let keyHeaders        = "BGLocationPush_headers"
    public static let keyParams         = "BGLocationPush_params"
    public static let keyExtras         = "BGLocationPush_extras"
    public static let keyRootProperty   = "BGLocationPush_rootProperty"
    public static let keyAuthorization  = "BGLocationPush_authorization"
    public static let keyAccessToken    = "BGLocationPush_accessToken"

    // Socket delivery (preferred channel for the extension). Written by the host
    // app via BackgroundGeolocation.setLocationPushConfig({...}). When socketUrl
    // is present the extension tries Socket.IO first, then falls back to REST.
    public static let keySocketUrl       = "BGLocationPush_socketUrl"
    public static let keySocketPath      = "BGLocationPush_socketPath"
    public static let keySocketEvent     = "BGLocationPush_socketEvent"
    public static let keySocketAuthToken = "BGLocationPush_socketAuthToken"
    public static let keySocketTimeout   = "BGLocationPush_socketTimeout"

    // REST fallback used when the socket fails: POST {latitude, longitude,
    // fcmToken, userCurrentTime} to fallbackUrl.
    public static let keyFallbackUrl     = "BGLocationPush_fallbackUrl"
    public static let keyFcmToken        = "BGLocationPush_fcmToken"

    // Host-defined payload shape for the upload (socket + REST fallback). A dict
    // whose values may contain tokens like "{latitude}", "{fcmToken}",
    // "{userCurrentTime}" that the deliverer substitutes with live values. When
    // absent, the deliverer uses its built-in default payload.
    public static let keyPayloadTemplate = "BGLocationPush_payloadTemplate"

    // The location push token (hex) the host app obtained from
    // `startMonitoringLocationPushesWithCompletion`. Stored in BOTH the standard
    // and the shared suite so JS can read it via getLocationPushToken().
    public static let keyLocationPushToken = "BGLocationManager_locationPushToken"

    /// Resolve the App Group identifier. Allows the host app to override the
    /// default at runtime by writing `keyAppGroup` into standard UserDefaults
    /// BEFORE the engine syncs config (rarely needed — the default is fine for
    /// most apps).
    @objc public static func resolveAppGroupIdentifier() -> String {
        if let override = UserDefaults.standard.string(forKey: keyAppGroup),
           !override.isEmpty {
            return override
        }
        return defaultAppGroupIdentifier
    }

    /// The shared UserDefaults suite, or nil if the App Group is not configured
    /// (entitlement missing). Callers must handle nil gracefully.
    @objc public static func sharedDefaults() -> UserDefaults? {
        UserDefaults(suiteName: resolveAppGroupIdentifier())
    }
}
