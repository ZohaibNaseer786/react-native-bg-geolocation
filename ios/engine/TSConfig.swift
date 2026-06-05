import Foundation

@objc public class TSConfig: NSObject, NSCoding {

    private static var _sharedInstance: TSConfig?
    private static let instanceLock = NSLock()
    private static let storageKey = "TSLocationManager_config"

    // MARK: - Singleton

    @objc public class func sharedInstance() -> TSConfig {
        instanceLock.lock()
        defer { instanceLock.unlock() }
        if _sharedInstance == nil {
            _sharedInstance = TSConfig.decode() ?? TSConfig()
        }
        return _sharedInstance!
    }

    @objc public class func decode(config dict: [String: Any]) -> TSConfig {
        let config = TSConfig()
        config.updateWithDictionary(dict)
        return config
    }

    @objc public class func uptime() -> TimeInterval {
        return ProcessInfo.processInfo.systemUptime
    }

    @objc public class func userDefaults() -> UserDefaults {
        return UserDefaults.standard
    }

    // MARK: - Sub-modules

    @objc public lazy var geolocation: TSGeolocationConfig = TSGeolocationConfig()
    @objc public lazy var http: TSHttpConfig = TSHttpConfig()
    @objc public lazy var logger: TSLoggerConfig = TSLoggerConfig()
    @objc public lazy var app: TSAppConfig = TSAppConfig()
    @objc public lazy var authorization: TSAuthorizationConfig = TSAuthorizationConfig()
    @objc public lazy var persistence: TSPersistenceConfig = TSPersistenceConfig()
    @objc public lazy var activity: TSActivityConfig = {
        let c = TSActivityConfig()
        return c
    }()

    // MARK: - Top-level state

    @objc public var enabled: Bool = false
    @objc public var isMoving: Bool = false
    @objc public var trackingMode: Int = 1
    @objc public var didLaunchInBackground: Bool = false
    @objc public var didRequestUpgradeLocationAuthorization: Bool = false
    @objc public var lastLocationAuthorizationStatus: Int = 0
    @objc public var iOSHasWarnedLocationServicesOff: Bool = false
    @objc public var schedulerEnabled: Bool = false
    @objc public var includeDeprecatedPropertiesInDictionary: Bool = false

    private var listeners: [String: [[String: Any]]] = [:]
    private var plugins: [String: AnyObject] = [:]
    private let listenersLock = NSLock()
    private let persistQueue = DispatchQueue(label: "TSConfig.persist")
    private var pendingPersist: Bool = false

    // MARK: - Init

    @objc public override init() {
        super.init()
        commonInitSetup()
    }

    @objc public required init?(coder: NSCoder) {
        super.init()
        commonInitSetup()
        if let data = coder.decodeObject(forKey: "geolocation") as? Data,
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            geolocation.updateWithDictionary(dict)
        }
        if let data = coder.decodeObject(forKey: "http") as? Data,
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            http.updateWithDictionary(dict)
        }
        if let data = coder.decodeObject(forKey: "logger") as? Data,
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            logger.updateWithDictionary(dict)
        }
        if let data = coder.decodeObject(forKey: "app") as? Data,
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            app.updateWithDictionary(dict)
        }
        enabled = coder.decodeBool(forKey: "enabled")
        isMoving = coder.decodeBool(forKey: "isMoving")
        trackingMode = coder.decodeInteger(forKey: "trackingMode")
        schedulerEnabled = coder.decodeBool(forKey: "schedulerEnabled")
    }

    @objc public func encode(with coder: NSCoder) {
        if let data = try? JSONSerialization.data(withJSONObject: geolocation.toDictionary()) { coder.encode(data, forKey: "geolocation") }
        if let data = try? JSONSerialization.data(withJSONObject: http.toDictionary()) { coder.encode(data, forKey: "http") }
        if let data = try? JSONSerialization.data(withJSONObject: logger.toDictionary()) { coder.encode(data, forKey: "logger") }
        if let data = try? JSONSerialization.data(withJSONObject: app.toDictionary()) { coder.encode(data, forKey: "app") }
        coder.encode(enabled, forKey: "enabled")
        coder.encode(isMoving, forKey: "isMoving")
        coder.encode(trackingMode, forKey: "trackingMode")
        coder.encode(schedulerEnabled, forKey: "schedulerEnabled")
    }

    @objc public func commonInitSetup() {
        applyDefaults()
    }

    @objc public func initPrivateForBoot() {
        didLaunchInBackground = true
    }

    // MARK: - Defaults

    @objc public func applyDefaults() {
        applyModuleDefaults()
    }

    @objc public func applyModuleDefaults() {
        geolocation.applyDefaults()
        http.applyDefaults()
        logger.applyDefaults()
        app.applyDefaults()
        authorization.applyDefaults()
        persistence.applyDefaults()
    }

    // MARK: - Module access

    @objc public func allModules() -> [TSConfigModuleBase] {
        return [geolocation, http, logger, app, authorization, persistence]
    }

    @objc public func moduleMap() -> [String: TSConfigModuleBase] {
        return [
            "geolocation": geolocation,
            "http": http,
            "logger": logger,
            "app": app,
            "authorization": authorization,
            "persistence": persistence
        ]
    }

    @objc public func module(forKey key: String) -> TSConfigModuleBase? {
        return moduleMap()[key]
    }

    @objc public func key(forModule module: TSConfigModuleBase) -> String? {
        return moduleMap().first(where: { $0.value === module })?.key
    }

    // MARK: - Update

    @objc public func updateWithDictionary(_ dict: [String: Any]) {
        updateWithDictionaryUnsafe(dict)
        persist()
    }

    @objc public func updateWithDictionaryUnsafe(_ dict: [String: Any]) {
        for (key, value) in dict {
            if let module = module(forKey: key), let subDict = value as? [String: Any] {
                module.updateWithDictionary(subDict)
            } else {
                applyTopLevelValue(value, forKey: key)
            }
        }
        flattenModulesFrom(dict)
    }

    @objc public func flattenedModules(from dict: [String: Any]) -> [String: Any] {
        var flattened: [String: Any] = [:]
        for module in allModules() {
            let specs = module.propertySpecs()
            for spec in specs {
                if let value = dict[spec.name] {
                    flattened[spec.name] = value
                }
            }
        }
        return flattened
    }

    @objc public func flattenModulesFrom(_ dict: [String: Any]) {
        for module in allModules() {
            let specs = module.propertySpecs()
            var moduleDict: [String: Any] = [:]
            for spec in specs {
                if let value = dict[spec.name] {
                    moduleDict[spec.name] = value
                }
            }
            if !moduleDict.isEmpty {
                module.updateWithDictionary(moduleDict)
            }
        }
    }

    private func applyTopLevelValue(_ value: Any, forKey key: String) {
        switch key {
        case "enabled": if let v = value as? Bool { enabled = v }
        case "isMoving", "is_moving": if let v = value as? Bool { isMoving = v }
        case "trackingMode": if let v = value as? Int { trackingMode = v }
        case "schedulerEnabled": if let v = value as? Bool { schedulerEnabled = v }
        default: break
        }
    }

    // MARK: - Batch update

    @objc public func batchUpdate(_ block: (TSConfig) -> Void) {
        block(self)
        persist()
    }

    // MARK: - Serialization

    @objc public func toDictionary() -> [String: Any] {
        return toDictionary(false)
    }

    @objc public func toDictionary(_ includeDeprecated: Bool) -> [String: Any] {
        return toDictionaryUnsafe(includeDeprecated)
    }

    @objc public func toDictionaryUnsafe(_ includeDeprecated: Bool) -> [String: Any] {
        var dict: [String: Any] = [:]
        dict["enabled"] = enabled
        dict["isMoving"] = isMoving
        dict["trackingMode"] = trackingMode
        dict["schedulerEnabled"] = schedulerEnabled

        let moduleDict = moduleMap()
        for (key, module) in moduleDict {
            dict[key] = module.toDictionary()
        }

        for module in allModules() {
            let moduleData = module.toDictionary()
            dict.merge(moduleData) { $1 }
        }

        return dict
    }

    @objc public func toJson() -> String? {
        let dict = toDictionary()
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @objc public func currentStateDictionary() -> [String: Any] {
        return toDictionary()
    }

    // MARK: - Persistence

    @objc public func persist() {
        persistQueue.async { self.persistUnsafe() }
    }

    @objc public func forcePersistNow() {
        persistUnsafe()
    }

    @objc public func persistUnsafe() {
        let data = try? NSKeyedArchiver.archivedData(withRootObject: self, requiringSecureCoding: false)
        UserDefaults.standard.set(data, forKey: TSConfig.storageKey)
        UserDefaults.standard.synchronize()
    }

    @objc public func _flushDefaults() {
        UserDefaults.standard.synchronize()
    }

    @objc public class func decode() -> TSConfig? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: TSConfig.self, from: data)
    }

    // MARK: - Listeners

    @objc public func addListener(_ property: String, callback: @escaping ([String: Any]) -> Void) -> Int {
        listenersLock.lock()
        defer { listenersLock.unlock() }
        let token = Int.random(in: 1...Int.max)
        var entry: [String: Any] = ["callback": callback, "token": token]
        if listeners[property] == nil { listeners[property] = [] }
        listeners[property]!.append(entry)
        return token
    }

    @objc public func onChange(_ block: @escaping ([String: Any]) -> Void) {
        _ = addListener("*", callback: block)
    }

    @objc public func removeListener(_ property: String, forProperty prop: String) {
    }

    @objc public func removeListener(_ property: String, token: Int) {
        listenersLock.lock()
        defer { listenersLock.unlock() }
        listeners[property]?.removeAll { ($0["token"] as? Int) == token }
    }

    @objc public func removeAllListeners(forProperty property: String) {
        listenersLock.lock()
        defer { listenersLock.unlock() }
        listeners.removeValue(forKey: property)
    }

    @objc public func removeAllListeners() {
        listenersLock.lock()
        defer { listenersLock.unlock() }
        listeners.removeAll()
    }

    @objc public func emitChangeEvent(_ event: String, value: Any?) {
        listenersLock.lock()
        let list = (listeners[event] ?? []) + (listeners["*"] ?? [])
        listenersLock.unlock()
        let payload: [String: Any] = ["event": event, "value": value ?? NSNull()]
        for entry in list {
            if let cb = entry["callback"] as? ([String: Any]) -> Void {
                cb(payload)
            }
        }
    }

    @objc public func emitModuleEvents(forPrefixes prefixes: [String]) {
        for prefix in prefixes {
            emitChangeEvent(prefix, value: nil)
        }
    }

    @objc public func moduleEventPrefixes(forChangedKeypaths keypaths: [String]) -> [String] {
        return keypaths
    }

    // MARK: - KVO

    @objc public func setupKVO() {
    }

    @objc public func setupModuleObservation() {
    }

    @objc public override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
    }

    // MARK: - Plugins

    @objc public func registerPlugin(_ plugin: AnyObject) {
        plugins[NSStringFromClass(type(of: plugin))] = plugin
    }

    @objc public func hasPlugin(forEvent event: String) -> Bool {
        return false
    }

    // MARK: - Convenience computed properties

    @objc public func hasSchedule() -> Bool {
        return app.hasSchedule
    }

    @objc public func hasTriggerActivities() -> Bool {
        return false
    }

    @objc public func hasValidUrl() -> Bool {
        return http.hasValidUrl
    }

    @objc public func isLocationTrackingMode() -> Bool {
        return trackingMode == 1
    }

    @objc public func isFirstBoot() -> Bool {
        return !UserDefaults.standard.bool(forKey: "TSLocationManager_booted")
    }

    @objc public func didDeviceReboot() -> Bool {
        let stored = UserDefaults.standard.double(forKey: "TSLocationManager_uptime")
        let current = ProcessInfo.processInfo.systemUptime
        return stored > current
    }

    @objc public func shouldPersist(_ location: TSLocation) -> Bool {
        return persistence.persistMode > 0
    }

    @objc public func isValue(_ value1: Any?, equalTo value2: Any?) -> Bool {
        guard let v1 = value1, let v2 = value2 else { return value1 == nil && value2 == nil }
        if let n1 = v1 as? NSObject, let n2 = v2 as? NSObject { return n1.isEqual(n2) }
        return false
    }

    // MARK: - State

    @objc public func reset() {
        resetUnsafe()
        persist()
    }

    @objc public func resetUnsafe() {
        enabled = false
        isMoving = false
        applyModuleDefaults()
    }

    @objc public func resetConfig(_ dict: [String: Any]) {
        resetUnsafe()
        updateWithDictionaryUnsafe(dict)
        persist()
    }

    @objc public func lockForInvalidLicense() {
        enabled = false
    }

    @objc public func validateLicense() {
        TSLicenseManager.sharedManager().validateLicense()
    }

    @objc public func migrateFromLegacyObject(_ legacy: AnyObject) {
    }

    @objc public func getLocationAuthorizationAlertStrings() -> [String: Any] {
        return [
            "title": "Background Location Access",
            "message": "This app requires location access to function properly.",
            "cancel": "Cancel",
            "settings": "Settings"
        ]
    }
}
