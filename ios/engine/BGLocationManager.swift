import Foundation
import CoreLocation
import UIKit

@objc public class BGLocationManager: NSObject {

    private static var _sharedInstance: BGLocationManager?
    private static let instanceLock = NSLock()

    @objc public class func sharedInstance() -> BGLocationManager {
        instanceLock.lock()
        defer { instanceLock.unlock() }
        if _sharedInstance == nil { _sharedInstance = BGLocationManager() }
        return _sharedInstance!
    }

    // MARK: - State

    @objc public var viewController: UIViewController?
    @objc public var beforeInsertBlock: ((BGLocation) -> BGLocation?)?

    private var locationManager: CLLocationManager?
    private var configChangeBufferTimer: Timer?
    private var isReady: Bool = false
    private let setupQueue = DispatchQueue(label: "BGLocationManager.setup")

    @objc public override init() {
        super.init()
        BGLocationManager.migrateLegacyKeysIfNeeded()
        setupCoreLocation()
    }

    /// One-time migration after the TS* → BG* rename. Copies any values still
    /// stored under the old `TSLocationManager_*` / `TSLocationPush_*` keys to
    /// their new `BG*` names, in both the standard suite and the App Group, so
    /// already-issued location-push tokens, odometer, and config survive the
    /// upgrade. Idempotent and cheap; runs once then no-ops.
    @objc public static func migrateLegacyKeysIfNeeded() {
        let suites: [UserDefaults?] = [.standard, BGLocationPushShared.sharedDefaults()]
        for case let defaults? in suites {
            guard !defaults.bool(forKey: "BGLocationManager_keysMigrated") else { continue }
            for (key, value) in defaults.dictionaryRepresentation() {
                guard key.hasPrefix("TSLocationManager_") || key.hasPrefix("TSLocationPush_") else { continue }
                let newKey = "BG" + key.dropFirst(2) // TS… -> BG…
                if defaults.object(forKey: newKey) == nil {
                    defaults.set(value, forKey: newKey)
                }
            }
            defaults.set(true, forKey: "BGLocationManager_keysMigrated")
        }
    }

    private func setupCoreLocation() {
        let configure = {
            let mgr = CLLocationManager()
            self.locationManager = mgr
            BGLocationAuthorization.configureShared(withLocationManager: mgr)
            BGLocationRequestService.configureShared(withLocationManager: mgr)
            BGTrackingService.sharedInstance().locationManager = mgr
            BGGeofenceManager.sharedInstance().locationManager = mgr
            // BGScheduler does not hold a locationManager reference

            // Configure the shared manager the instant it exists —
            // allowsBackgroundLocationUpdates DEFAULTS TO false, and iOS refuses
            // background delivery / pauses GPS without it. Doing this here (not
            // only in start()) means the kill-state auto-resume path and any
            // direct SLC/region arming get a correctly-configured manager.
            BGTrackingService.sharedInstance().configureLocationManager(mgr)

            // A CLLocationManager has exactly one delegate. Route every callback
            // through BGCLRouter, which fans out to the services above. This MUST
            // be the only place `mgr.delegate` is assigned.
            mgr.delegate = BGCLRouter.sharedInstance()

            // Kill-state / cold-boot auto-resume. On an iOS background relaunch
            // (significant-change or region exit after system termination) JS may never
            // call ready(), so the engine must re-arm monitoring itself or the OS
            // wake is wasted and nothing is delivered. Only resume when tracking
            // was persisted enabled (or startOnBoot fired) — i.e. the user had
            // tracking on and didn't stop it. ready() is idempotent (guarded by
            // isReady), so a later JS ready() is a no-op for start.
            let cfg = BGConfig.sharedInstance()
            let launchedInBackground = BGAppState.sharedInstance().didLaunchInBackground
            NSLog("[BGGEO] setupCoreLocation auto-resume check: enabled=\(cfg.enabled) startOnBoot=\(cfg.app.startOnBoot) launchedInBackground=\(launchedInBackground)")
            if cfg.enabled || (cfg.app.startOnBoot && launchedInBackground) {
                NSLog("[BGGEO] auto-resuming engine natively (kill-state path)")
                self.ready()
            }
        }

        if Thread.isMainThread {
            configure()
        } else {
            DispatchQueue.main.sync(execute: configure)
        }
    }

    // MARK: - Lifecycle

    @objc public func ready() {
        guard !isReady else { return }
        isReady = true
        let config = BGConfig.sharedInstance()
        // Mark the app as having booted at least once so isFirstBoot() returns false on next launch.
        UserDefaults.standard.set(true, forKey: "BGLocationManager_booted")
        BGLog.sharedInstance().configure()
        BGHttpService.sharedInstance().startMonitoring()
        BGLocationDAO.sharedInstance()

        let appState = BGAppState.sharedInstance()
        config.didLaunchInBackground = appState.didLaunchInBackground
        if config.app.startOnBoot && config.didLaunchInBackground {
            doStart(true)
        }

        if config.enabled {
            doStart(config.isMoving)
        }

        // Drain records left by an interrupted background request immediately.
        // This does not depend on React Native listeners or a later reachability
        // transition, so a location-triggered cold launch can deliver natively.
        BGHttpService.sharedInstance().resumePendingAutoSync()

        // Clear the background-launch flag UNCONDITIONALLY once it has been read
        // into config — otherwise (when ready() runs via the cfg.enabled branch
        // instead of startOnBoot) the flag leaks into the NEXT normal foreground
        // launch, corrupting launch classification.
        UserDefaults.standard.removeObject(forKey: "BGLocationManager_didLaunchInBackground")

        // Mirror the HTTP config into the App Group so the Location Push Service
        // Extension can POST locations to the same server while the app is killed.
        syncConfigToAppGroup()

        BGAppState.sharedInstance().clientReady = true
    }

    /// Writes the current HTTP config (url, headers, params, auth token, etc.)
    /// into the App Group shared UserDefaults. The CLLocationPushServiceExtension
    /// runs in a separate process and reads this to know where/how to upload the
    /// location it captures after an APNs location push. Safe no-op if the App
    /// Group entitlement is not configured.
    @objc public func syncConfigToAppGroup() {
        guard let defaults = BGLocationPushShared.sharedDefaults() else {
            NSLog("[BGGEO] App Group not configured — Location Push config not synced")
            return
        }
        let config = BGConfig.sharedInstance()
        let http = config.http

        defaults.set(http.url, forKey: BGLocationPushShared.keyUrl)
        defaults.set(http.method, forKey: BGLocationPushShared.keyMethod)
        defaults.set(http.headers, forKey: BGLocationPushShared.keyHeaders)
        defaults.set(http.params, forKey: BGLocationPushShared.keyParams)
        defaults.set(http.rootProperty, forKey: BGLocationPushShared.keyRootProperty)

        let auth = config.authorization
        if let token = auth.accessToken, !token.isEmpty {
            defaults.set(token, forKey: BGLocationPushShared.keyAccessToken)
        } else {
            defaults.removeObject(forKey: BGLocationPushShared.keyAccessToken)
        }

        NSLog("[BGGEO] Synced HTTP config to App Group (url=\(http.url)) for Location Push Extension")
    }

    /// Host-app-supplied delivery config for the Location Push Service Extension.
    /// Lets the app hand the extension a preferred socket channel (and any extra
    /// REST overrides). Keys: socketUrl, socketPath, socketEvent, socketAuthToken,
    /// socketTimeout, url, accessToken, extras. Persisted to the App Group.
    @objc public func setLocationPushConfig(_ config: [String: Any]) {
        guard let defaults = BGLocationPushShared.sharedDefaults() else {
            NSLog("[BGGEO] App Group not configured — Location Push config not stored")
            return
        }

        // Partial update: only touch keys PRESENT in the dict. An explicit
        // NSNull clears; an absent key is left unchanged (so a later
        // fcmToken-only call doesn't wipe the socket config).
        func apply(_ defaultsKey: String, _ srcKey: String) {
            guard let value = config[srcKey] else { return }
            if value is NSNull { defaults.removeObject(forKey: defaultsKey) }
            else { defaults.set(value, forKey: defaultsKey) }
        }

        apply(BGLocationPushShared.keySocketUrl, "socketUrl")
        apply(BGLocationPushShared.keySocketPath, "socketPath")
        apply(BGLocationPushShared.keySocketEvent, "socketEvent")
        apply(BGLocationPushShared.keySocketAuthToken, "socketAuthToken")
        apply(BGLocationPushShared.keySocketTimeout, "socketTimeout")
        apply(BGLocationPushShared.keyFallbackUrl, "fallbackUrl")
        apply(BGLocationPushShared.keyFcmToken, "fcmToken")

        // Optional REST overrides (otherwise the values synced from http config win).
        if let url = config["url"] { defaults.set(url, forKey: BGLocationPushShared.keyUrl) }
        if let token = config["accessToken"] { defaults.set(token, forKey: BGLocationPushShared.keyAccessToken) }
        if let extras = config["extras"] as? [String: Any] {
            defaults.set(extras, forKey: BGLocationPushShared.keyExtras)
        }

        NSLog("[BGGEO] Stored Location Push delivery config (socketUrl=\(config["socketUrl"] ?? "nil"))")
    }

    @objc public func start() {
        let config = BGConfig.sharedInstance()
        config.enabled = true
        // Start must be durable before returning to JS. If the process is
        // terminated immediately after the user taps Start, an async archive
        // can be lost and the next Core Location launch cannot auto-resume.
        config.forcePersistNow()
        syncConfigToAppGroup()
        doStart(config.isMoving)
    }

    @objc public func doStart(_ isMoving: Bool) {
        let config = BGConfig.sharedInstance()
        config.validateLicense()

        let tracking = BGTrackingService.sharedInstance()
        tracking.beforeInsertBlock = beforeInsertBlock
        tracking.start(isMoving)
        BGLiveActivityManager.shared.startIfNeeded(isMoving: isMoving)
        BGTrackingAudioManager.shared.startIfNeeded()

        if config.app.preventSuspend {
            BGBackgroundTaskManager.sharedInstance().startPreventSuspend(.invalid)
        }

        if config.hasSchedule() {
            startSchedule()
        }

        startGeofences()
        BGEventBus.sharedInstance().emit(BGEventNames.enabledChange, payload: ["enabled": true])
    }

    @objc public func stop() {
        let config = BGConfig.sharedInstance()
        config.enabled = false
        config.isMoving = false
        config.forcePersistNow()

        BGTrackingService.sharedInstance().stop()
        BGLiveActivityManager.shared.end()
        BGTrackingAudioManager.shared.stop()
        BGBackgroundTaskManager.sharedInstance().stopPreventSuspend(.invalid)
        BGGeofenceManager.sharedInstance().stop()
        BGScheduler.sharedInstance().stop()
        BGEventBus.sharedInstance().emit(BGEventNames.enabledChange, payload: ["enabled": false])
    }

    @objc public var enabled: Bool {
        return BGConfig.sharedInstance().enabled
    }

    // MARK: - Pace

    @objc public func changePace(_ isMoving: Bool) {
        BGTrackingService.sharedInstance().changePace(isMoving)
    }

    @objc public func setPace(_ isMoving: Bool) {
        changePace(isMoving)
    }

    // MARK: - Current position

    @objc public func getCurrentPosition(_ request: BGCurrentPositionRequest) {
        BGTrackingService.sharedInstance().getCurrentPosition(request)
    }

    // MARK: - Watch position

    @objc public func watchPosition(_ request: BGWatchPositionRequest) {
        // Bridge the watch request onto a stream and drive its success block with
        // a BGLocation on every emitted fix (previously the passed request was
        // dropped and a blank stream with no callback was started instead).
        let stream = BGStreamLocationRequest()
        stream.interval = request.interval
        stream.desiredAccuracy = request.desiredAccuracy
        stream.persist = request.persist
        stream.extras = request.extras
        stream.success = { location in
            guard let cl = location as? CLLocation else { return }
            let tsLocation = BGLocation(location: cl, type: "watch", extras: request.extras as? [String: Any])
            if request.persist {
                _ = BGLocationDAO.sharedInstance().create(tsLocation, error: nil)
            }
            request.success?(tsLocation)
        }
        _ = BGLocationRequestService.sharedInstance().startStream(stream)
    }

    @objc public func stopWatchPosition(_ watchId: Int) {
        // The bridge supports a single active watch, so stop all streams rather
        // than relying on a stream id the JS layer never receives.
        BGLocationRequestService.sharedInstance().stopAllStreams()
    }

    // MARK: - Geofences

    @objc public func addGeofence(_ geofence: BGGeofence, success: (() -> Void)?, failure: ((Error) -> Void)?) {
        BGGeofenceManager.sharedInstance().create(geofence, success: success, failure: failure)
    }

    @objc public func addGeofences(_ geofences: [BGGeofence], success: (() -> Void)?, failure: ((Error) -> Void)?) {
        for geofence in geofences {
            BGGeofenceManager.sharedInstance().create(geofence, success: nil, failure: nil)
        }
        success?()
    }

    @objc public func removeGeofence(_ identifier: String, success: (() -> Void)?, failure: ((Error) -> Void)?) {
        BGGeofenceManager.sharedInstance().destroy(identifier, success: success, failure: failure)
    }

    @objc public func removeGeofences(_ identifiers: [String], success: (() -> Void)?, failure: ((Error) -> Void)?) {
        for id in identifiers {
            BGGeofenceManager.sharedInstance().destroy(id, success: nil, failure: nil)
        }
        success?()
    }

    @objc public func removeGeofences() {
        BGGeofenceDAO.sharedInstance().destroyAll()
        BGGeofenceManager.sharedInstance().stopMonitoringGeofences()
    }

    @objc public func getGeofence(_ identifier: String, success: ((BGGeofence) -> Void)?, failure: ((Error) -> Void)?) {
        if let geofence = BGGeofenceDAO.sharedInstance().find(identifier) {
            success?(geofence)
        } else {
            failure?(NSError(domain: "BGLocationManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "Geofence not found: \(identifier)"]))
        }
    }

    @objc public func getGeofences(_ success: (([BGGeofence]) -> Void)?, failure: ((Error) -> Void)?) {
        success?(BGGeofenceDAO.sharedInstance().all())
    }

    @objc public func getGeofences() -> [BGGeofence] {
        return BGGeofenceDAO.sharedInstance().all()
    }

    @objc public func geofenceExists(_ identifier: String, callback: ((Bool) -> Void)?) {
        callback?(BGGeofenceDAO.sharedInstance().exists(identifier))
    }

    @objc public func startGeofences() {
        BGGeofenceManager.sharedInstance().start()
    }

    // MARK: - Locations

    @objc public func getLocations(_ success: (([[String: Any]]) -> Void)?, failure: ((Error) -> Void)?) {
        let records = BGLocationDAO.sharedInstance().all()
        success?(records)
    }

    @objc public func getCount() -> Int {
        return BGLocationDAO.sharedInstance().getCount()
    }

    @objc public func insertLocation(_ location: BGLocation, success: ((BGLocation) -> Void)?, failure: ((Error) -> Void)?) {
        if BGLocationDAO.sharedInstance().create(location, error: nil) {
            success?(location)
        } else {
            failure?(NSError(domain: "BGLocationManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to insert location"]))
        }
    }

    @objc public func persistLocation(_ location: BGLocation) {
        _ = BGLocationDAO.sharedInstance().create(location, error: nil)
    }

    @objc public func destroyLocation(_ uuid: String) -> Bool {
        return BGLocationDAO.sharedInstance().destroy(uuid)
    }

    @objc public func destroyLocation(_ uuid: String, success: (() -> Void)?, failure: ((Error) -> Void)?) {
        if BGLocationDAO.sharedInstance().destroy(uuid) {
            success?()
        } else {
            failure?(NSError(domain: "BGLocationManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to destroy location"]))
        }
    }

    @objc public func destroyLocations(_ failure: ((Error) -> Void)?) {
        BGLocationDAO.sharedInstance().clear()
    }

    @objc public func destroyLocations() {
        BGLocationDAO.sharedInstance().clear()
    }

    @objc public func clearDatabase() {
        destroyLocations()
    }

    @objc public func sync(_ success: (([[String: Any]]) -> Void)?, failure: ((Error) -> Void)?) {
        BGHttpService.sharedInstance().flush({ response in
            let records = BGLocationDAO.sharedInstance().all()
            success?(records)
        }, failure: failure)
    }

    @objc public func getStationaryLocation() -> CLLocation? {
        return BGTrackingService.sharedInstance().stationaryLocation
    }

    // MARK: - Odometer

    @objc public func getOdometer() -> Double {
        return BGOdometer.sharedInstance().getOdometer()
    }

    @objc public func setOdometer(_ value: Double, request: BGCurrentPositionRequest?) {
        BGTrackingService.sharedInstance().setOdometer(value, request: request)
    }

    // MARK: - Schedule

    @objc public func startSchedule() {
        guard let mgr = locationManager else { return }
        _ = BGScheduler.sharedInstance().start(withSchedule: BGConfig.sharedInstance().app.schedule)
    }

    @objc public func stopSchedule() {
        BGScheduler.sharedInstance().stop()
    }

    // MARK: - Log

    @objc public func getLog(_ query: LogQuery?, success: (([String: Any]) -> Void)?, failure: ((Error) -> Void)?) {
        let q = query ?? LogQuery()
        let entries = BGLog.sharedInstance().getLog(q)
        success?(["log": entries])
    }

    @objc public func getLog(_ query: LogQuery?, failure: ((Error) -> Void)?) {
        getLog(query, success: nil, failure: failure)
    }

    @objc public func emailLog(_ to: String, query: LogQuery?, success: (() -> Void)?, failure: ((Error) -> Void)?) {
        let q = query ?? LogQuery()
        BGLog.sharedInstance().emailLog(to, query: q, success: success, failure: failure)
    }

    @objc public func emailLog(_ to: String, success: (() -> Void)?, failure: ((Error) -> Void)?) {
        emailLog(to, query: nil, success: success, failure: failure)
    }

    @objc public func uploadLog(_ url: String, query: LogQuery?, success: (([String: Any]) -> Void)?, failure: ((Error) -> Void)?) {
        let q = query ?? LogQuery()
        BGLog.sharedInstance().uploadLog(url, query: q, success: success, failure: failure)
    }

    @objc public func destroyLog() {
        BGLog.sharedInstance().destroy()
    }

    @objc public func setLogLevel(_ level: Int) {
        BGLog.sharedInstance().setLogLevel(level)
    }

    @objc public func log(_ level: String, message: String) {
        BGLog.sharedInstance().notify(message, debug: level == "debug")
    }

    @objc public func error(_ level: String, message: String) {
        BGLog.sharedInstance().alert(level, message: message)
    }

    @objc public func playSound(_ soundId: SystemSoundID) {
        BGLog.sharedInstance().playSound(soundId)
    }

    // MARK: - Provider state

    @objc public func getProviderState() -> [String: Any] {
        let status = CLLocationManager.authorizationStatus()
        return [
            "status": status.rawValue,
            "enabled": CLLocationManager.locationServicesEnabled(),
            "gps": CLLocationManager.locationServicesEnabled(),
            "network": false,
            "accuracyAuthorization": 1
        ]
    }

    @objc public func getState() -> [String: Any] {
        var state = BGConfig.sharedInstance().currentStateDictionary()
        state["liveActivity"] = BGLiveActivityManager.shared.stateDictionary()
        state["trackingAudio"] = BGTrackingAudioManager.shared.stateDictionary()
        return state
    }

    // MARK: - Hardware availability

    @objc public func isLocationServicesEnabled() -> Bool {
        return CLLocationManager.locationServicesEnabled()
    }

    @objc public func isPowerSaveMode() -> Bool {
        return ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    @objc public func isAccelerometerAvailable() -> Bool {
        return BGMotionDetector.sharedInstance().isAccelerometerAvailable()
    }

    @objc public func isGyroAvailable() -> Bool {
        return BGMotionDetector.sharedInstance().isGyroAvailable()
    }

    @objc public func isDeviceMotionAvailable() -> Bool {
        return BGMotionDetector.sharedInstance().isDeviceMotionAvailable()
    }

    @objc public func isMagnetometerAvailable() -> Bool {
        return BGMotionDetector.sharedInstance().isMagnetometerAvailable()
    }

    @objc public func isMotionHardwareAvailable() -> Bool {
        return BGMotionDetector.motionHardwareAvailable()
    }

    @objc public func isRotationAvailable() -> Bool {
        return BGMotionDetector.sharedInstance().isGyroAvailable()
    }

    // MARK: - Permissions

    @objc public func requestPermission(_ success: (() -> Void)?, failure: ((Error) -> Void)?) {
        BGLocationAuthorization.sharedInstance().updateDesiredPolicyFromConfig()
        BGLocationAuthorization.sharedInstance().requestAuthorization { status, error in
            if let error = error {
                failure?(error)
            } else {
                success?()
            }
        }
    }

    @objc public func requestTemporaryFullAccuracy(_ purposeKey: String, success: (() -> Void)?, failure: ((Error) -> Void)?) {
        BGLocationAuthorization.sharedInstance().requestTemporaryFullAccuracy(purposeKey, success: success, failure: failure)
    }

    // MARK: - Background task

    @objc public func createBackgroundTask() -> UIBackgroundTaskIdentifier {
        return BGBackgroundTaskManager.sharedInstance().createBackgroundTask()
    }

    @objc public func stopBackgroundTask(_ taskId: UIBackgroundTaskIdentifier) {
        BGBackgroundTaskManager.sharedInstance().stopBackgroundTask(taskId)
    }

    // MARK: - Listeners

    @objc public func onLocation(_ success: ((BGLocation) -> Void)?, failure: ((Error) -> Void)?) {
        BGEventManager.sharedInstance().addLocationListener(success: { location in
            if let loc = location as? BGLocation { success?(loc) }
        }, failure: { payload in
            if let err = payload as? Error { failure?(err) }
        })
    }

    @objc public func onMotionChange(_ success: ((BGLocation) -> Void)?, failure: ((Error) -> Void)?) {
        _ = BGEventManager.sharedInstance().addListener(BGEventNames.motionChangeComplete, callback: { payload in
            if let loc = payload as? BGLocation { success?(loc) }
        })
    }

    @objc public func onActivityChange(_ success: ((BGMotionActivity) -> Void)?) {
        _ = BGEventBus.sharedInstance().on(BGEventNames.activityChange) { payload in
            if let activity = payload as? BGMotionActivity { success?(activity) }
        }
    }

    @objc public func onGeofence(_ success: ((BGGeofenceEvent) -> Void)?) {
        _ = BGEventBus.sharedInstance().on(BGEventNames.geofence) { payload in
            if let event = payload as? BGGeofenceEvent { success?(event) }
        }
    }

    @objc public func onGeofencesChange(_ success: ((BGGeofencesChangeEvent) -> Void)?) {
    }

    @objc public func onHttp(_ success: (([String: Any]) -> Void)?) {
        _ = BGEventBus.sharedInstance().on(BGEventNames.http) { payload in
            if let dict = payload as? [String: Any] { success?(dict) }
        }
    }

    @objc public func onHeartbeat(_ success: ((BGHeartbeatEvent) -> Void)?) {
        _ = BGEventBus.sharedInstance().on(BGEventNames.heartbeat) { payload in
            if let event = payload as? BGHeartbeatEvent { success?(event) }
        }
    }

    @objc public func onSchedule(_ success: ((BGScheduleEvent) -> Void)?) {
        _ = BGEventBus.sharedInstance().on(BGEventNames.schedule) { payload in
            if let event = payload as? BGScheduleEvent { success?(event) }
        }
    }

    @objc public func onEnabledChange(_ success: ((Bool) -> Void)?) {
        _ = BGEventBus.sharedInstance().on(BGEventNames.enabledChange) { payload in
            if let dict = payload as? [String: Any], let enabled = dict["enabled"] as? Bool {
                success?(enabled)
            }
        }
    }

    @objc public func onConnectivityChange(_ success: ((Bool) -> Void)?) {
        _ = BGEventBus.sharedInstance().on(BGEventNames.connectivityChange) { payload in
            if let dict = payload as? [String: Any], let connected = dict["connected"] as? Bool {
                success?(connected)
            }
        }
    }

    @objc public func onPowerSaveChange(_ success: ((Bool) -> Void)?) {
        _ = BGEventBus.sharedInstance().on(BGEventNames.powerSaveChange) { payload in
            if let dict = payload as? [String: Any], let enabled = dict["isPowerSaveMode"] as? Bool {
                success?(enabled)
            }
        }
    }

    @objc public func onAuthorization(_ success: ((BGAuthorizationEvent) -> Void)?) {
        _ = BGEventBus.sharedInstance().on(BGEventNames.authorization) { payload in
            if let event = payload as? BGAuthorizationEvent { success?(event) }
        }
    }

    @objc public func onProviderChange(_ success: ((BGProviderChangeEvent) -> Void)?) {
        _ = BGEventBus.sharedInstance().on(BGEventNames.providerChange) { payload in
            if let event = payload as? BGProviderChangeEvent { success?(event) }
        }
    }

    // MARK: - Remove listeners

    @objc public func removeListener(_ event: String, callback: AnyObject) {
    }

    @objc public func removeListener(_ event: String, token: Int) {
        BGEventBus.sharedInstance().off(event, token: String(token))
    }

    @objc public func removeListeners(_ event: String) {
        BGEventBus.sharedInstance().offAll(event)
    }

    @objc public func removeListenersForEvent(_ event: String) {
        removeListeners(event)
    }

    @objc public func removeListeners() {
        BGEventBus.sharedInstance().offAll()
    }

    // MARK: - View controller

    public func setViewController(_ vc: UIViewController) {
        viewController = vc
    }
}

import AudioToolbox
