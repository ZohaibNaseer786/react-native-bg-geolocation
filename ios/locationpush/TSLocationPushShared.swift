//
//  TSLocationPushShared.swift
//
//  Constants shared between the host app (TSLocationManager engine) and the
//  CLLocationPushServiceExtension. Because the extension runs in a SEPARATE
//  process, the only channel between them is an App Group shared UserDefaults
//  suite. Both sides MUST agree on the suite name and the keys below.
//
//  This file is compiled into BOTH:
//    1. The `BgGeolocation` pod (so TSLocationManager can WRITE the config)
//    2. The Location Push Service Extension target (so it can READ the config)
//
//  ── HOST-APP INTEGRATION ──────────────────────────────────────────────────
//  Consumers of this package must:
//    • Create an App Group with the identifier in `appGroupIdentifier` below
//      (or override it — see TSLocationPushShared.resolveAppGroupIdentifier()).
//    • Add that App Group to BOTH the main app target and the extension target.
//  If you use a different App Group id, change `defaultAppGroupIdentifier` here
//  (it is the single source of truth) and rebuild.
//

import Foundation

@objc public final class TSLocationPushShared: NSObject {

    /// The default App Group identifier. The example app uses this value; it is
    /// the single place to change if you adopt a different group id.
    public static let defaultAppGroupIdentifier = "group.com.masjidpilot.staging"

    // UserDefaults keys written by the host app and read by the extension.
    public static let keyAppGroup       = "TSLocationPush_appGroup"
    public static let keyUrl            = "TSLocationPush_url"
    public static let keyMethod         = "TSLocationPush_method"
    public static let keyHeaders        = "TSLocationPush_headers"
    public static let keyParams         = "TSLocationPush_params"
    public static let keyExtras         = "TSLocationPush_extras"
    public static let keyRootProperty   = "TSLocationPush_rootProperty"
    public static let keyAuthorization  = "TSLocationPush_authorization"
    public static let keyAccessToken    = "TSLocationPush_accessToken"

    // Socket delivery (preferred channel for the extension). Written by the host
    // app via BackgroundGeolocation.setLocationPushConfig({...}). When socketUrl
    // is present the extension tries Socket.IO first, then falls back to REST.
    public static let keySocketUrl       = "TSLocationPush_socketUrl"
    public static let keySocketPath      = "TSLocationPush_socketPath"
    public static let keySocketEvent     = "TSLocationPush_socketEvent"
    public static let keySocketAuthToken = "TSLocationPush_socketAuthToken"
    public static let keySocketTimeout   = "TSLocationPush_socketTimeout"

    // REST fallback used when the socket fails: POST {latitude, longitude,
    // fcmToken, userCurrentTime} to fallbackUrl.
    public static let keyFallbackUrl     = "TSLocationPush_fallbackUrl"
    public static let keyFcmToken        = "TSLocationPush_fcmToken"

    // The location push token (hex) the host app obtained from
    // `startMonitoringLocationPushesWithCompletion`. Stored in BOTH the standard
    // and the shared suite so JS can read it via getLocationPushToken().
    public static let keyLocationPushToken = "TSLocationManager_locationPushToken"

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
