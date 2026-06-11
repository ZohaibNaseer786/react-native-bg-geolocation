import Foundation
import CoreLocation

@objc public class BGConfigBuilder: NSObject {

    @objc public var url: String?
    @objc public var method: String = "POST"
    @objc public var headers: [String: String]?
    @objc public var params: [String: Any]?
    @objc public var authorization: [String: Any]?
    @objc public var httpRootProperty: String = "location"
    @objc public var httpTimeout: Double = 60.0
    @objc public var autoSync: Bool = true
    @objc public var autoSyncThreshold: Int = 0
    @objc public var batchSync: Bool = false
    @objc public var maxBatchSize: Int = -1
    @objc public var disableAutoSyncOnCellular: Bool = false

    @objc public var desiredAccuracy: Int = 0
    @objc public var distanceFilter: Double = 10.0
    @objc public var stationaryRadius: Double = 25.0
    @objc public var locationTimeout: Double = 60.0
    @objc public var stopTimeout: Double = 5.0
    @objc public var activityType: String = "Other"
    @objc public var pausesLocationUpdatesAutomatically: Bool = false
    @objc public var showsBackgroundLocationIndicator: Bool = false
    @objc public var useSignificantChangesOnly: Bool = false
    @objc public var locationAuthorizationRequest: String = "Always"
    @objc public var locationAuthorizationAlert: [String: Any]?
    @objc public var disableLocationAuthorizationAlert: Bool = false
    @objc public var geofenceProximityRadius: Double = 1000.0
    @objc public var geofenceInitialTriggerEntry: Bool = true
    @objc public var disableElasticity: Bool = false
    @objc public var elasticityMultiplier: Double = 1.0
    @objc public var desiredOdometerAccuracy: Double = 100.0

    @objc public var stopOnTerminate: Bool = true
    @objc public var startOnBoot: Bool = false
    @objc public var preventSuspend: Bool = false
    @objc public var heartbeatInterval: Double = 60.0
    @objc public var schedule: [String] = []
    @objc public var stopOnStationary: Bool = false
    @objc public var stopAfterElapsedMinutes: Double = 0
    @objc public var stopDetectionDelay: Double = 0
    @objc public var triggerActivities: String = "in_vehicle,on_bicycle,on_foot,running,walking"

    @objc public var logLevel: Int = 5
    @objc public var logMaxDays: Int = 3
    @objc public var debug: Bool = false

    @objc public var persistMode: Int = 2
    @objc public var maxDaysToPersist: Int = 1
    @objc public var maxRecordsToPersist: Int = -1
    @objc public var locationsOrderDirection: String = "ASC"
    @objc public var geofenceTemplate: String?
    @objc public var locationTemplate: String?
    @objc public var extras: [String: Any]?
    @objc public var enableTimestampMeta: Bool = false

    @objc public var isMoving: Bool = false
    @objc public var activityRecognitionInterval: Double = 10000.0
    @objc public var minimumActivityRecognitionConfidence: Int = 75
    @objc public var disableMotionActivityUpdates: Bool = false
    @objc public var disableStopDetection: Bool = false

    private var dirtyKeys: Set<String> = []

    @objc public override init() {
        super.init()
        applyDefaults()
    }

    @objc public func applyDefaults() {
    }

    @objc public func setDirty(_ key: String) {
        dirtyKeys.insert(key)
    }

    @objc public func eachDirtyProperty(_ block: (String, Any?) -> Void) {
        for key in dirtyKeys {
            block(key, value(forKey: key, withType: ""))
        }
    }

    public func value(forKey key: String, withType type: String) -> Any? {
        return nil
    }

    @objc public func valueForKey(_ key: String, withType type: String) -> Any? {
        return value(forKey: key, withType: type)
    }

    @objc public class func decodeActivityType(_ type: String) -> CLActivityType {
        return BGGeolocationConfig.activityType(fromString: type) ?? .other
    }

    @objc public class func decodeDesiredAccuracy(_ accuracy: Any) -> CLLocationAccuracy {
        return BGGeolocationConfig.decodeDesiredAccuracy(accuracy)
    }

    @objc public class func eachProperty(_ obj: AnyObject, callback: (String, String, Any?) -> Void) {
    }

    @objc public class func getPropertyType(_ key: String) -> String {
        return "string"
    }

    @objc public class func value(_ value1: Any?, isEqualTo value2: Any?, withType type: String) -> Bool {
        guard let v1 = value1, let v2 = value2 else { return value1 == nil && value2 == nil }
        if let n1 = v1 as? NSObject, let n2 = v2 as? NSObject { return n1.isEqual(n2) }
        return false
    }

    @objc public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [:]
        if let url = url { dict["url"] = url }
        dict["method"] = method
        if let headers = headers { dict["headers"] = headers }
        if let params = params { dict["params"] = params }
        dict["httpRootProperty"] = httpRootProperty
        dict["httpTimeout"] = httpTimeout
        dict["autoSync"] = autoSync
        dict["autoSyncThreshold"] = autoSyncThreshold
        dict["batchSync"] = batchSync
        dict["maxBatchSize"] = maxBatchSize
        dict["desiredAccuracy"] = desiredAccuracy
        dict["distanceFilter"] = distanceFilter
        dict["stationaryRadius"] = stationaryRadius
        dict["locationTimeout"] = locationTimeout
        dict["stopTimeout"] = stopTimeout
        dict["activityType"] = activityType
        dict["pausesLocationUpdatesAutomatically"] = pausesLocationUpdatesAutomatically
        dict["useSignificantChangesOnly"] = useSignificantChangesOnly
        dict["locationAuthorizationRequest"] = locationAuthorizationRequest
        dict["geofenceProximityRadius"] = geofenceProximityRadius
        dict["geofenceInitialTriggerEntry"] = geofenceInitialTriggerEntry
        dict["disableElasticity"] = disableElasticity
        dict["elasticityMultiplier"] = elasticityMultiplier
        dict["stopOnTerminate"] = stopOnTerminate
        dict["startOnBoot"] = startOnBoot
        dict["preventSuspend"] = preventSuspend
        dict["heartbeatInterval"] = heartbeatInterval
        dict["schedule"] = schedule
        dict["logLevel"] = logLevel
        dict["logMaxDays"] = logMaxDays
        dict["debug"] = debug
        dict["persistMode"] = persistMode
        dict["maxDaysToPersist"] = maxDaysToPersist
        dict["maxRecordsToPersist"] = maxRecordsToPersist
        dict["isMoving"] = isMoving
        dict["activityRecognitionInterval"] = activityRecognitionInterval
        dict["disableMotionActivityUpdates"] = disableMotionActivityUpdates
        return dict
    }

    @objc public override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
    }
}

@objc public class BGConfigOLD: NSObject, NSCoding {

    private static var _sharedInstance: BGConfigOLD?
    private static let instanceLock = NSLock()
    private static let storageKey = "TSLocationManager_config_v2"

    @objc public class func sharedInstance() -> BGConfigOLD {
        instanceLock.lock()
        defer { instanceLock.unlock() }
        if _sharedInstance == nil {
            _sharedInstance = BGConfigOLD()
        }
        return _sharedInstance!
    }

    @objc public class func decodeConfig(_ dict: [String: Any]) -> BGConfigOLD {
        let config = BGConfigOLD()
        config.updateWithDictionary(dict)
        return config
    }

    @objc public class func uptime() -> TimeInterval {
        return ProcessInfo.processInfo.systemUptime
    }

    @objc public class func userDefaults() -> UserDefaults {
        return UserDefaults.standard
    }

    @objc public class func classForPropertyName(_ name: String, fromObject obj: AnyObject) -> String {
        return "NSString"
    }

    @objc public class func setValue(_ value: Any?, forObject obj: AnyObject, forKey key: String, withType type: String) {
        obj.setValue(value, forKey: key)
    }

    // MARK: - Properties

    @objc public var url: String?
    @objc public var method: String = "POST"
    @objc public var headers: [String: String]?
    @objc public var params: [String: Any]?
    @objc public var authorization: [String: Any]?
    @objc public var httpRootProperty: String = "location"
    @objc public var httpTimeout: Double = 60.0
    @objc public var autoSync: Bool = true
    @objc public var autoSyncThreshold: Int = 0
    @objc public var batchSync: Bool = false
    @objc public var maxBatchSize: Int = -1
    @objc public var disableAutoSyncOnCellular: Bool = false

    @objc public var desiredAccuracy: Int = 0
    @objc public var distanceFilter: Double = 10.0
    @objc public var stationaryRadius: Double = 25.0
    @objc public var locationTimeout: Double = 60.0
    @objc public var stopTimeout: Double = 5.0
    @objc public var activityType: String = "Other"
    @objc public var pausesLocationUpdatesAutomatically: Bool = false
    @objc public var showsBackgroundLocationIndicator: Bool = false
    @objc public var useSignificantChangesOnly: Bool = false
    @objc public var locationAuthorizationRequest: String = "Always"
    @objc public var locationAuthorizationAlert: [String: Any]?
    @objc public var disableLocationAuthorizationAlert: Bool = false
    @objc public var geofenceProximityRadius: Double = 1000.0
    @objc public var geofenceInitialTriggerEntry: Bool = true
    @objc public var disableElasticity: Bool = false
    @objc public var elasticityMultiplier: Double = 1.0
    @objc public var desiredOdometerAccuracy: Double = 100.0

    @objc public var stopOnTerminate: Bool = true
    @objc public var startOnBoot: Bool = false
    @objc public var preventSuspend: Bool = false
    @objc public var heartbeatInterval: Double = 60.0
    @objc public var schedule: [String] = []
    @objc public var stopOnStationary: Bool = false
    @objc public var stopAfterElapsedMinutes: Double = 0
    @objc public var stopDetectionDelay: Double = 0
    @objc public var triggerActivities: String = "in_vehicle,on_bicycle,on_foot,running,walking"

    @objc public var logLevel: Int = 5
    @objc public var logMaxDays: Int = 3
    @objc public var debug: Bool = false

    @objc public var persistMode: Int = 2
    @objc public var maxDaysToPersist: Int = 1
    @objc public var maxRecordsToPersist: Int = -1
    @objc public var locationsOrderDirection: String = "ASC"
    @objc public var geofenceTemplate: String?
    @objc public var locationTemplate: String?
    @objc public var extras: [String: Any]?
    @objc public var enableTimestampMeta: Bool = false

    @objc public var enabled: Bool = false
    @objc public var isMoving: Bool = false
    @objc public var trackingMode: Int = 1
    @objc public var didLaunchInBackground: Bool = false
    @objc public var didRequestUpgradeLocationAuthorization: Bool = false
    @objc public var lastLocationAuthorizationStatus: Int = 0
    @objc public var iOSHasWarnedLocationServicesOff: Bool = false
    @objc public var schedulerEnabled: Bool = false
    @objc public var odometer: Double = 0

    @objc public var activityRecognitionInterval: Double = 10000.0
    @objc public var minimumActivityRecognitionConfidence: Int = 75
    @objc public var disableMotionActivityUpdates: Bool = false
    @objc public var disableStopDetection: Bool = false

    private var listeners: [String: [(String, ([String: Any]) -> Void)]] = [:]
    private var dirtyKeys: Set<String> = []
    private var plugins: [String: AnyObject] = [:]
    private let listenersLock = NSLock()

    @objc public override init() {
        super.init()
        applyDefaults()
    }

    @objc public required init?(coder: NSCoder) {
        super.init()
        applyDefaults()
        if let dict = coder.decodeObject(forKey: "config") as? [String: Any] {
            applyDictionary(dict)
        }
        enabled = coder.decodeBool(forKey: "enabled")
        isMoving = coder.decodeBool(forKey: "isMoving")
        odometer = coder.decodeDouble(forKey: "odometer")
    }

    @objc public func encode(with coder: NSCoder) {
        coder.encode(toDictionary(), forKey: "config")
        coder.encode(enabled, forKey: "enabled")
        coder.encode(isMoving, forKey: "isMoving")
        coder.encode(odometer, forKey: "odometer")
    }

    @objc public func applyDefaults() {
    }

    // MARK: - Update

    @objc public func updateWithDictionary(_ dict: [String: Any]) {
        applyDictionary(dict)
        persist()
        ts_emitDirtyChanges()
    }

    @objc public func updateWithBlock(_ block: (BGConfigBuilder) -> Void) {
        let builder = BGConfigBuilder()
        block(builder)
        updateWithDictionary(builder.toDictionary())
    }

    private func applyDictionary(_ dict: [String: Any]) {
        if let v = dict["url"] as? String { url = v }
        if let v = dict["method"] as? String { method = v }
        if let v = dict["headers"] as? [String: String] { headers = v }
        if let v = dict["params"] as? [String: Any] { params = v }
        if let v = dict["httpRootProperty"] as? String { httpRootProperty = v }
        if let v = dict["httpTimeout"] as? Double { httpTimeout = v }
        if let v = dict["autoSync"] as? Bool { autoSync = v }
        if let v = dict["autoSyncThreshold"] as? Int { autoSyncThreshold = v }
        if let v = dict["batchSync"] as? Bool { batchSync = v }
        if let v = dict["maxBatchSize"] as? Int { maxBatchSize = v }
        if let v = dict["desiredAccuracy"] as? Int { desiredAccuracy = v }
        if let v = dict["distanceFilter"] as? Double { distanceFilter = v }
        if let v = dict["stationaryRadius"] as? Double { stationaryRadius = v }
        if let v = dict["locationTimeout"] as? Double { locationTimeout = v }
        if let v = dict["stopTimeout"] as? Double { stopTimeout = v }
        if let v = dict["activityType"] as? String { activityType = v }
        if let v = dict["pausesLocationUpdatesAutomatically"] as? Bool { pausesLocationUpdatesAutomatically = v }
        if let v = dict["showsBackgroundLocationIndicator"] as? Bool { showsBackgroundLocationIndicator = v }
        if let v = dict["useSignificantChangesOnly"] as? Bool { useSignificantChangesOnly = v }
        if let v = dict["locationAuthorizationRequest"] as? String { locationAuthorizationRequest = v }
        if let v = dict["geofenceProximityRadius"] as? Double { geofenceProximityRadius = v }
        if let v = dict["geofenceInitialTriggerEntry"] as? Bool { geofenceInitialTriggerEntry = v }
        if let v = dict["disableElasticity"] as? Bool { disableElasticity = v }
        if let v = dict["elasticityMultiplier"] as? Double { elasticityMultiplier = v }
        if let v = dict["stopOnTerminate"] as? Bool { stopOnTerminate = v }
        if let v = dict["startOnBoot"] as? Bool { startOnBoot = v }
        if let v = dict["preventSuspend"] as? Bool { preventSuspend = v }
        if let v = dict["heartbeatInterval"] as? Double { heartbeatInterval = v }
        if let v = dict["schedule"] as? [String] { schedule = v }
        if let v = dict["logLevel"] as? Int { logLevel = v }
        if let v = dict["logMaxDays"] as? Int { logMaxDays = v }
        if let v = dict["debug"] as? Bool { debug = v }
        if let v = dict["persistMode"] as? Int { persistMode = v }
        if let v = dict["maxDaysToPersist"] as? Int { maxDaysToPersist = v }
        if let v = dict["maxRecordsToPersist"] as? Int { maxRecordsToPersist = v }
        if let v = dict["locationsOrderDirection"] as? String { locationsOrderDirection = v }
        if let v = dict["extras"] as? [String: Any] { extras = v }
        if let v = dict["enableTimestampMeta"] as? Bool { enableTimestampMeta = v }
        if let v = dict["enabled"] as? Bool { enabled = v }
        if let v = dict["isMoving"] as? Bool { isMoving = v }
        if let v = dict["odometer"] as? Double { odometer = v }
        if let v = dict["activityRecognitionInterval"] as? Double { activityRecognitionInterval = v }
        if let v = dict["disableMotionActivityUpdates"] as? Bool { disableMotionActivityUpdates = v }
        if let v = dict["authorization"] as? [String: Any] { authorization = v }
        if let v = dict["geofenceTemplate"] as? String { geofenceTemplate = v }
        if let v = dict["locationTemplate"] as? String { locationTemplate = v }
        if let v = dict["triggerActivities"] as? String { triggerActivities = v }
        if let v = dict["stopAfterElapsedMinutes"] as? Double { stopAfterElapsedMinutes = v }
        if let v = dict["stopDetectionDelay"] as? Double { stopDetectionDelay = v }
    }

    // MARK: - Persistence

    @objc public func persist() {
        let data = try? NSKeyedArchiver.archivedData(withRootObject: self, requiringSecureCoding: false)
        UserDefaults.standard.set(data, forKey: BGConfigOLD.storageKey)
        UserDefaults.standard.synchronize()
    }

    // MARK: - Serialization

    @objc public func toDictionary() -> [String: Any] {
        return toDictionary(false)
    }

    @objc public func toDictionary(_ includeState: Bool) -> [String: Any] {
        var dict: [String: Any] = [:]
        if let url = url { dict["url"] = url }
        dict["method"] = method
        if let headers = headers { dict["headers"] = headers }
        dict["httpRootProperty"] = httpRootProperty
        dict["httpTimeout"] = httpTimeout
        dict["autoSync"] = autoSync
        dict["autoSyncThreshold"] = autoSyncThreshold
        dict["batchSync"] = batchSync
        dict["maxBatchSize"] = maxBatchSize
        dict["desiredAccuracy"] = desiredAccuracy
        dict["distanceFilter"] = distanceFilter
        dict["stationaryRadius"] = stationaryRadius
        dict["locationTimeout"] = locationTimeout
        dict["stopTimeout"] = stopTimeout
        dict["activityType"] = activityType
        dict["pausesLocationUpdatesAutomatically"] = pausesLocationUpdatesAutomatically
        dict["showsBackgroundLocationIndicator"] = showsBackgroundLocationIndicator
        dict["useSignificantChangesOnly"] = useSignificantChangesOnly
        dict["locationAuthorizationRequest"] = locationAuthorizationRequest
        dict["geofenceProximityRadius"] = geofenceProximityRadius
        dict["geofenceInitialTriggerEntry"] = geofenceInitialTriggerEntry
        dict["disableElasticity"] = disableElasticity
        dict["elasticityMultiplier"] = elasticityMultiplier
        dict["stopOnTerminate"] = stopOnTerminate
        dict["startOnBoot"] = startOnBoot
        dict["preventSuspend"] = preventSuspend
        dict["heartbeatInterval"] = heartbeatInterval
        dict["schedule"] = schedule
        dict["logLevel"] = logLevel
        dict["logMaxDays"] = logMaxDays
        dict["debug"] = debug
        dict["persistMode"] = persistMode
        dict["maxDaysToPersist"] = maxDaysToPersist
        dict["maxRecordsToPersist"] = maxRecordsToPersist
        dict["locationsOrderDirection"] = locationsOrderDirection
        dict["enableTimestampMeta"] = enableTimestampMeta
        dict["isMoving"] = isMoving
        dict["enabled"] = enabled
        dict["odometer"] = odometer
        dict["activityRecognitionInterval"] = activityRecognitionInterval
        dict["disableMotionActivityUpdates"] = disableMotionActivityUpdates
        dict["triggerActivities"] = triggerActivities
        dict["stopAfterElapsedMinutes"] = stopAfterElapsedMinutes
        dict["stopDetectionDelay"] = stopDetectionDelay
        if let extras = extras { dict["extras"] = extras }
        if let geofenceTemplate = geofenceTemplate { dict["geofenceTemplate"] = geofenceTemplate }
        if let locationTemplate = locationTemplate { dict["locationTemplate"] = locationTemplate }
        if let authorization = authorization { dict["authorization"] = authorization }
        return dict
    }

    @objc public func toJson() -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: toDictionary()) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Listeners

    @objc public func onChange(_ keyPath: String, callback: @escaping ([String: Any]) -> Void) {
        listenersLock.lock()
        defer { listenersLock.unlock() }
        if listeners[keyPath] == nil { listeners[keyPath] = [] }
        let token = UUID().uuidString
        listeners[keyPath]!.append((token, callback))
    }

    @objc public func removeListeners(forKeyPath keyPath: String) {
        listenersLock.lock()
        defer { listenersLock.unlock() }
        listeners.removeValue(forKey: keyPath)
    }

    @objc public func removeListeners() {
        listenersLock.lock()
        defer { listenersLock.unlock() }
        listeners.removeAll()
    }

    @objc public func fireOnChange(_ keyPath: String, value: Any?) {
        listenersLock.lock()
        let list = listeners[keyPath] ?? []
        listenersLock.unlock()
        let payload: [String: Any] = ["value": value ?? NSNull()]
        for (_, cb) in list { cb(payload) }
    }

    // MARK: - Dirty tracking

    @objc public func ts_addDirty(_ key: String) {
        dirtyKeys.insert(key)
    }

    @objc public func ts_drainDirty() {
        dirtyKeys.removeAll()
    }

    private func ts_emitDirtyChanges() {
        let dirty = dirtyKeys
        ts_drainDirty()
        for key in dirty {
            fireOnChange(key, value: value(forKey: key))
        }
    }

    // MARK: - Computed properties

    @objc public func hasSchedule() -> Bool {
        return !schedule.isEmpty
    }

    @objc public func hasTriggerActivities() -> Bool {
        return !triggerActivities.isEmpty
    }

    @objc public func hasTriggerActivity(_ activity: String) -> Bool {
        return triggerActivities.contains(activity)
    }

    @objc public func hasValidUrl() -> Bool {
        guard let url = url, !url.isEmpty else { return false }
        return URL(string: url) != nil
    }

    @objc public func hasPluginForEvent(_ event: String) -> Bool {
        return plugins[event] != nil
    }

    @objc public func isLocationTrackingMode() -> Bool {
        return trackingMode == 1
    }

    @objc public func isFirstBoot() -> Bool {
        return !UserDefaults.standard.bool(forKey: "TSLocationManager_booted")
    }

    @objc public func didDeviceReboot() -> Bool {
        let stored = UserDefaults.standard.double(forKey: "TSLocationManager_uptime")
        return stored > ProcessInfo.processInfo.systemUptime
    }

    @objc public func getPausesLocationUpdates() -> Bool {
        return pausesLocationUpdatesAutomatically
    }

    @objc public func shouldPersist(_ location: BGLocation) -> Bool {
        return persistMode > 0
    }

    @objc public func getLocationAuthorizationAlertStrings() -> [String: Any] {
        return locationAuthorizationAlert ?? [
            "title": "Background Location Access",
            "message": "This app requires location access.",
            "cancel": "Cancel",
            "settings": "Settings"
        ]
    }

    @objc public func incrementOdometer(_ distance: Double) {
        odometer += distance
    }

    // MARK: - Plugins

    @objc public func registerPlugin(_ plugin: AnyObject) {
        plugins[NSStringFromClass(type(of: plugin))] = plugin
    }

    // MARK: - Module event observation

    @objc public func ts_observeStateProperties() {
    }

    @objc public func ts_getStateProperties() -> [String] {
        return []
    }

    @objc public func ts_registerModulesForEventRegistry() {
    }

    @objc public func ts_emitModuleLeafDiffs(forProperty property: String, oldModule: AnyObject?, newModule: AnyObject?) {
    }

    // MARK: - Reset

    @objc public func reset() {
        reset([:])
    }

    @objc public func reset(_ dict: [String: Any]) {
        applyDefaults()
        if !dict.isEmpty { applyDictionary(dict) }
        persist()
    }

    // MARK: - KVO

    @objc public override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        guard let keyPath = keyPath else { return }
        fireOnChange(keyPath, value: change?[.newKey])
    }
}
