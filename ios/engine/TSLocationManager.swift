import Foundation
import CoreLocation
import UIKit

@objc public class TSLocationManager: NSObject {

    private static var _sharedInstance: TSLocationManager?
    private static let instanceLock = NSLock()

    @objc public class func sharedInstance() -> TSLocationManager {
        instanceLock.lock()
        defer { instanceLock.unlock() }
        if _sharedInstance == nil { _sharedInstance = TSLocationManager() }
        return _sharedInstance!
    }

    // MARK: - State

    @objc public var viewController: UIViewController?
    @objc public var beforeInsertBlock: ((TSLocation) -> TSLocation?)?

    private var locationManager: CLLocationManager?
    private var configChangeBufferTimer: Timer?
    private var isReady: Bool = false
    private let setupQueue = DispatchQueue(label: "TSLocationManager.setup")

    @objc public override init() {
        super.init()
        setupCoreLocation()
    }

    private func setupCoreLocation() {
        DispatchQueue.main.async {
            let mgr = CLLocationManager()
            self.locationManager = mgr
            TSLocationAuthorization.configureShared(withLocationManager: mgr)
            TSLocationRequestService.configureShared(withLocationManager: mgr)
            TSTrackingService.sharedInstance().locationManager = mgr
            TSGeofenceManager.sharedInstance().locationManager = mgr
            // TSScheduler does not hold a locationManager reference
        }
    }

    // MARK: - Lifecycle

    @objc public func ready() {
        guard !isReady else { return }
        isReady = true
        let config = TSConfig.sharedInstance()
        // Mark the app as having booted at least once so isFirstBoot() returns false on next launch.
        UserDefaults.standard.set(true, forKey: "TSLocationManager_booted")
        TSLog.sharedInstance().configure()
        TSHttpService.sharedInstance().startMonitoring()
        TSLocationDAO.sharedInstance()

        if config.app.startOnBoot && config.didLaunchInBackground {
            doStart(true)
        }

        if config.enabled {
            doStart(config.isMoving)
        }

        TSAppState.sharedInstance().clientReady = true
    }

    @objc public func start() {
        let config = TSConfig.sharedInstance()
        config.enabled = true
        config.persist()
        doStart(config.isMoving)
    }

    @objc public func doStart(_ isMoving: Bool) {
        let config = TSConfig.sharedInstance()
        config.validateLicense()

        let tracking = TSTrackingService.sharedInstance()
        tracking.beforeInsertBlock = beforeInsertBlock
        tracking.start(isMoving)

        if config.app.preventSuspend {
            TSBackgroundTaskManager.sharedInstance().startPreventSuspend(.invalid)
        }

        if config.hasSchedule() {
            startSchedule()
        }

        startGeofences()
        TSEventBus.sharedInstance().emit(TSEventNames.enabledChange, payload: ["enabled": true])
    }

    @objc public func stop() {
        let config = TSConfig.sharedInstance()
        config.enabled = false
        config.isMoving = false
        config.persist()

        TSTrackingService.sharedInstance().stop()
        TSBackgroundTaskManager.sharedInstance().stopPreventSuspend(.invalid)
        TSGeofenceManager.sharedInstance().stop()
        TSScheduler.sharedInstance().stop()
        TSEventBus.sharedInstance().emit(TSEventNames.enabledChange, payload: ["enabled": false])
    }

    @objc public var enabled: Bool {
        return TSConfig.sharedInstance().enabled
    }

    // MARK: - Pace

    @objc public func changePace(_ isMoving: Bool) {
        TSTrackingService.sharedInstance().changePace(isMoving)
    }

    @objc public func setPace(_ isMoving: Bool) {
        changePace(isMoving)
    }

    // MARK: - Current position

    @objc public func getCurrentPosition(_ request: TSCurrentPositionRequest) {
        TSTrackingService.sharedInstance().getCurrentPosition(request)
    }

    // MARK: - Watch position

    @objc public func watchPosition(_ request: TSWatchPositionRequest) {
        TSLocationRequestService.sharedInstance().startStream(TSStreamLocationRequest())
    }

    @objc public func stopWatchPosition(_ watchId: Int) {
        TSLocationRequestService.sharedInstance().stopStream(watchId)
    }

    // MARK: - Geofences

    @objc public func addGeofence(_ geofence: TSGeofence, success: (() -> Void)?, failure: ((Error) -> Void)?) {
        TSGeofenceManager.sharedInstance().create(geofence, success: success, failure: failure)
    }

    @objc public func addGeofences(_ geofences: [TSGeofence], success: (() -> Void)?, failure: ((Error) -> Void)?) {
        for geofence in geofences {
            TSGeofenceManager.sharedInstance().create(geofence, success: nil, failure: nil)
        }
        success?()
    }

    @objc public func removeGeofence(_ identifier: String, success: (() -> Void)?, failure: ((Error) -> Void)?) {
        TSGeofenceManager.sharedInstance().destroy(identifier, success: success, failure: failure)
    }

    @objc public func removeGeofences(_ identifiers: [String], success: (() -> Void)?, failure: ((Error) -> Void)?) {
        for id in identifiers {
            TSGeofenceManager.sharedInstance().destroy(id, success: nil, failure: nil)
        }
        success?()
    }

    @objc public func removeGeofences() {
        TSGeofenceDAO.sharedInstance().destroyAll()
        TSGeofenceManager.sharedInstance().stopMonitoringGeofences()
    }

    @objc public func getGeofence(_ identifier: String, success: ((TSGeofence) -> Void)?, failure: ((Error) -> Void)?) {
        if let geofence = TSGeofenceDAO.sharedInstance().find(identifier) {
            success?(geofence)
        } else {
            failure?(NSError(domain: "TSLocationManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "Geofence not found: \(identifier)"]))
        }
    }

    @objc public func getGeofences(_ success: (([TSGeofence]) -> Void)?, failure: ((Error) -> Void)?) {
        success?(TSGeofenceDAO.sharedInstance().all())
    }

    @objc public func getGeofences() -> [TSGeofence] {
        return TSGeofenceDAO.sharedInstance().all()
    }

    @objc public func geofenceExists(_ identifier: String, callback: ((Bool) -> Void)?) {
        callback?(TSGeofenceDAO.sharedInstance().exists(identifier))
    }

    @objc public func startGeofences() {
        TSGeofenceManager.sharedInstance().start()
    }

    // MARK: - Locations

    @objc public func getLocations(_ success: (([[String: Any]]) -> Void)?, failure: ((Error) -> Void)?) {
        let records = TSLocationDAO.sharedInstance().all()
        success?(records)
    }

    @objc public func getCount() -> Int {
        return TSLocationDAO.sharedInstance().getCount()
    }

    @objc public func insertLocation(_ location: TSLocation, success: ((TSLocation) -> Void)?, failure: ((Error) -> Void)?) {
        if TSLocationDAO.sharedInstance().create(location, error: nil) {
            success?(location)
        } else {
            failure?(NSError(domain: "TSLocationManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to insert location"]))
        }
    }

    @objc public func persistLocation(_ location: TSLocation) {
        _ = TSLocationDAO.sharedInstance().create(location, error: nil)
    }

    @objc public func destroyLocation(_ uuid: String) -> Bool {
        return TSLocationDAO.sharedInstance().destroy(uuid)
    }

    @objc public func destroyLocation(_ uuid: String, success: (() -> Void)?, failure: ((Error) -> Void)?) {
        if TSLocationDAO.sharedInstance().destroy(uuid) {
            success?()
        } else {
            failure?(NSError(domain: "TSLocationManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to destroy location"]))
        }
    }

    @objc public func destroyLocations(_ failure: ((Error) -> Void)?) {
        TSLocationDAO.sharedInstance().clear()
    }

    @objc public func destroyLocations() {
        TSLocationDAO.sharedInstance().clear()
    }

    @objc public func clearDatabase() {
        destroyLocations()
    }

    @objc public func sync(_ success: (([[String: Any]]) -> Void)?, failure: ((Error) -> Void)?) {
        TSHttpService.sharedInstance().flush({ response in
            let records = TSLocationDAO.sharedInstance().all()
            success?(records)
        }, failure: failure)
    }

    @objc public func getStationaryLocation() -> CLLocation? {
        return TSTrackingService.sharedInstance().stationaryLocation
    }

    // MARK: - Odometer

    @objc public func getOdometer() -> Double {
        return TSOdometer.sharedInstance().getOdometer()
    }

    @objc public func setOdometer(_ value: Double, request: TSCurrentPositionRequest?) {
        TSTrackingService.sharedInstance().setOdometer(value, request: request)
    }

    // MARK: - Schedule

    @objc public func startSchedule() {
        guard let mgr = locationManager else { return }
        _ = TSScheduler.sharedInstance().start(withSchedule: TSConfig.sharedInstance().app.schedule)
    }

    @objc public func stopSchedule() {
        TSScheduler.sharedInstance().stop()
    }

    // MARK: - Log

    @objc public func getLog(_ query: LogQuery?, success: (([String: Any]) -> Void)?, failure: ((Error) -> Void)?) {
        let q = query ?? LogQuery()
        let entries = TSLog.sharedInstance().getLog(q)
        success?(["log": entries])
    }

    @objc public func getLog(_ query: LogQuery?, failure: ((Error) -> Void)?) {
        getLog(query, success: nil, failure: failure)
    }

    @objc public func emailLog(_ to: String, query: LogQuery?, success: (() -> Void)?, failure: ((Error) -> Void)?) {
        let q = query ?? LogQuery()
        TSLog.sharedInstance().emailLog(to, query: q, success: success, failure: failure)
    }

    @objc public func emailLog(_ to: String, success: (() -> Void)?, failure: ((Error) -> Void)?) {
        emailLog(to, query: nil, success: success, failure: failure)
    }

    @objc public func uploadLog(_ url: String, query: LogQuery?, success: (([String: Any]) -> Void)?, failure: ((Error) -> Void)?) {
        let q = query ?? LogQuery()
        TSLog.sharedInstance().uploadLog(url, query: q, success: success, failure: failure)
    }

    @objc public func destroyLog() {
        TSLog.sharedInstance().destroy()
    }

    @objc public func setLogLevel(_ level: Int) {
        TSLog.sharedInstance().setLogLevel(level)
    }

    @objc public func log(_ level: String, message: String) {
        TSLog.sharedInstance().notify(message, debug: level == "debug")
    }

    @objc public func error(_ level: String, message: String) {
        TSLog.sharedInstance().alert(level, message: message)
    }

    @objc public func playSound(_ soundId: SystemSoundID) {
        TSLog.sharedInstance().playSound(soundId)
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
        return TSConfig.sharedInstance().currentStateDictionary()
    }

    // MARK: - Hardware availability

    @objc public func isLocationServicesEnabled() -> Bool {
        return CLLocationManager.locationServicesEnabled()
    }

    @objc public func isPowerSaveMode() -> Bool {
        return ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    @objc public func isAccelerometerAvailable() -> Bool {
        return TSMotionDetector.sharedInstance().isAccelerometerAvailable()
    }

    @objc public func isGyroAvailable() -> Bool {
        return TSMotionDetector.sharedInstance().isGyroAvailable()
    }

    @objc public func isDeviceMotionAvailable() -> Bool {
        return TSMotionDetector.sharedInstance().isDeviceMotionAvailable()
    }

    @objc public func isMagnetometerAvailable() -> Bool {
        return TSMotionDetector.sharedInstance().isMagnetometerAvailable()
    }

    @objc public func isMotionHardwareAvailable() -> Bool {
        return TSMotionDetector.motionHardwareAvailable()
    }

    @objc public func isRotationAvailable() -> Bool {
        return TSMotionDetector.sharedInstance().isGyroAvailable()
    }

    // MARK: - Permissions

    @objc public func requestPermission(_ success: (() -> Void)?, failure: ((Error) -> Void)?) {
        TSLocationAuthorization.sharedInstance().requestAuthorization { status, error in
            if let error = error {
                failure?(error)
            } else {
                success?()
            }
        }
    }

    @objc public func requestTemporaryFullAccuracy(_ purposeKey: String, success: (() -> Void)?, failure: ((Error) -> Void)?) {
        TSLocationAuthorization.sharedInstance().requestTemporaryFullAccuracy(purposeKey, success: success, failure: failure)
    }

    // MARK: - Background task

    @objc public func createBackgroundTask() -> UIBackgroundTaskIdentifier {
        return TSBackgroundTaskManager.sharedInstance().createBackgroundTask()
    }

    @objc public func stopBackgroundTask(_ taskId: UIBackgroundTaskIdentifier) {
        TSBackgroundTaskManager.sharedInstance().stopBackgroundTask(taskId)
    }

    // MARK: - Listeners

    @objc public func onLocation(_ success: ((TSLocation) -> Void)?, failure: ((Error) -> Void)?) {
        TSEventManager.sharedInstance().addLocationListener(success: { location in
            if let loc = location as? TSLocation { success?(loc) }
        }, failure: { payload in
            if let err = payload as? Error { failure?(err) }
        })
    }

    @objc public func onMotionChange(_ success: ((TSLocation) -> Void)?, failure: ((Error) -> Void)?) {
        _ = TSEventManager.sharedInstance().addListener(TSEventNames.motionChangeComplete, callback: { payload in
            if let loc = payload as? TSLocation { success?(loc) }
        })
    }

    @objc public func onActivityChange(_ success: ((TSMotionActivity) -> Void)?) {
        _ = TSEventBus.sharedInstance().on(TSEventNames.activityChange) { payload in
            if let activity = payload as? TSMotionActivity { success?(activity) }
        }
    }

    @objc public func onGeofence(_ success: ((TSGeofenceEvent) -> Void)?) {
        _ = TSEventBus.sharedInstance().on(TSEventNames.geofence) { payload in
            if let event = payload as? TSGeofenceEvent { success?(event) }
        }
    }

    @objc public func onGeofencesChange(_ success: ((TSGeofencesChangeEvent) -> Void)?) {
    }

    @objc public func onHttp(_ success: (([String: Any]) -> Void)?) {
        _ = TSEventBus.sharedInstance().on(TSEventNames.http) { payload in
            if let dict = payload as? [String: Any] { success?(dict) }
        }
    }

    @objc public func onHeartbeat(_ success: ((TSHeartbeatEvent) -> Void)?) {
        _ = TSEventBus.sharedInstance().on(TSEventNames.heartbeat) { payload in
            if let event = payload as? TSHeartbeatEvent { success?(event) }
        }
    }

    @objc public func onSchedule(_ success: ((TSScheduleEvent) -> Void)?) {
        _ = TSEventBus.sharedInstance().on(TSEventNames.schedule) { payload in
            if let event = payload as? TSScheduleEvent { success?(event) }
        }
    }

    @objc public func onEnabledChange(_ success: ((Bool) -> Void)?) {
        _ = TSEventBus.sharedInstance().on(TSEventNames.enabledChange) { payload in
            if let dict = payload as? [String: Any], let enabled = dict["enabled"] as? Bool {
                success?(enabled)
            }
        }
    }

    @objc public func onConnectivityChange(_ success: ((Bool) -> Void)?) {
        _ = TSEventBus.sharedInstance().on(TSEventNames.connectivityChange) { payload in
            if let dict = payload as? [String: Any], let connected = dict["connected"] as? Bool {
                success?(connected)
            }
        }
    }

    @objc public func onPowerSaveChange(_ success: ((Bool) -> Void)?) {
        _ = TSEventBus.sharedInstance().on(TSEventNames.powerSaveChange) { payload in
            if let dict = payload as? [String: Any], let enabled = dict["isPowerSaveMode"] as? Bool {
                success?(enabled)
            }
        }
    }

    @objc public func onAuthorization(_ success: ((TSAuthorizationEvent) -> Void)?) {
        _ = TSEventBus.sharedInstance().on(TSEventNames.authorization) { payload in
            if let event = payload as? TSAuthorizationEvent { success?(event) }
        }
    }

    @objc public func onProviderChange(_ success: ((TSProviderChangeEvent) -> Void)?) {
        _ = TSEventBus.sharedInstance().on(TSEventNames.providerChange) { payload in
            if let event = payload as? TSProviderChangeEvent { success?(event) }
        }
    }

    // MARK: - Remove listeners

    @objc public func removeListener(_ event: String, callback: AnyObject) {
    }

    @objc public func removeListener(_ event: String, token: Int) {
        TSEventBus.sharedInstance().off(event, token: String(token))
    }

    @objc public func removeListeners(_ event: String) {
        TSEventBus.sharedInstance().offAll(event)
    }

    @objc public func removeListenersForEvent(_ event: String) {
        removeListeners(event)
    }

    @objc public func removeListeners() {
        TSEventBus.sharedInstance().offAll()
    }

    // MARK: - View controller

    public func setViewController(_ vc: UIViewController) {
        viewController = vc
    }
}

import AudioToolbox
